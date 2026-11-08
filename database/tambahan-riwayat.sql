-- =====================================================================
-- RIWAYAT PERUBAHAN: mencatat siapa mengubah apa (hanya pemilik yang bisa melihat)
-- Aman dijalankan berulang kali. Jalankan sekali di Supabase > SQL Editor.
-- Catatan lebih dari 90 hari dihapus otomatis supaya database tetap ringan.
-- =====================================================================

create table if not exists activity_log (
  id      bigint generated always as identity primary key,
  shop_id uuid not null references shops(id) on delete cascade,
  at      timestamptz not null default now(),
  actor   text not null default 'Sistem',
  entity  text not null,
  summary text not null
);
create index if not exists activity_log_shop_at on activity_log (shop_id, at desc);

alter table activity_log enable row level security;
drop policy if exists activity_log_read on activity_log;
create policy activity_log_read on activity_log for select
  using (has_role(shop_id, array['owner']::member_role[]));
-- tidak ada kebijakan tulis: hanya pemicu di bawah yang bisa mengisi
revoke all on activity_log from anon;
grant select on activity_log to authenticated;

create or replace function log_act(p_shop uuid, p_entity text, p_summary text)
returns void language plpgsql security definer set search_path = public, auth as $$
declare who text;
begin
  select coalesce(nullif(m.name,''), u.email, 'Sistem') into who
  from auth.users u left join members m on m.user_id = u.id and m.shop_id = p_shop
  where u.id = auth.uid();
  insert into activity_log(shop_id, entity, actor, summary)
  values (p_shop, p_entity, coalesce(who,'Sistem'), left(p_summary, 300));
  if random() < 0.02 then
    delete from activity_log where shop_id = p_shop and at < now() - interval '90 days';
  end if;
exception when others then
  null; -- riwayat tidak boleh menggagalkan pekerjaan pengguna
end $$;
revoke all on function log_act(uuid,text,text) from public, anon, authenticated;

create or replace function fmt_rp(n numeric) returns text language sql immutable as $$
  select 'Rp' || replace(to_char(round(coalesce(n,0)), 'FM999,999,999,999,990'), ',', '.')
$$;

-- ---------- pembayaran ----------
create or replace function trg_log_payments() returns trigger language plpgsql security definer set search_path = public, auth as $$
declare r payments; cn text;
begin
  r := case when tg_op = 'DELETE' then old else new end;
  if tg_op = 'DELETE' and not exists (select 1 from trips where id = r.trip_id) then return old; end if;
  select name into cn from customers where id = r.customer_id;
  if tg_op = 'INSERT' then perform log_act(r.shop_id,'pembayaran','Pembayaran '||fmt_rp(r.amount)||' dari '||coalesce(cn,'pelanggan')||' dicatat');
  elsif tg_op = 'DELETE' then perform log_act(r.shop_id,'pembayaran','Pembayaran '||fmt_rp(r.amount)||' dari '||coalesce(cn,'pelanggan')||' dihapus'); end if;
  return r;
end $$;
drop trigger if exists log_payments on payments;
create trigger log_payments after insert or delete on payments for each row execute function trg_log_payments();

-- ---------- pesanan ----------
create or replace function trg_log_lines() returns trigger language plpgsql security definer set search_path = public, auth as $$
declare r order_lines; cn text;
begin
  r := case when tg_op = 'DELETE' then old else new end;
  if tg_op = 'DELETE' and not exists (select 1 from trips where id = r.trip_id) then return old; end if;
  if tg_op = 'DELETE' and not exists (select 1 from customers where id = r.customer_id) then return old; end if;
  select name into cn from customers where id = r.customer_id;
  if tg_op = 'INSERT' then perform log_act(r.shop_id,'pesanan','Pesanan '||coalesce(cn,'?')||': '||r.code||' x'||r.qty||' masuk');
  elsif tg_op = 'UPDATE' then
    if new.cancelled is distinct from old.cancelled then
      perform log_act(r.shop_id,'pesanan','Pesanan '||coalesce(cn,'?')||': '||r.code||' x'||r.qty||case when new.cancelled then ' dibatalkan' else ' dipulihkan' end);
    elsif new.qty is distinct from old.qty then
      perform log_act(r.shop_id,'pesanan','Pesanan '||coalesce(cn,'?')||': '||r.code||' jumlah '||old.qty||' menjadi '||new.qty);
    end if;
  else perform log_act(r.shop_id,'pesanan','Pesanan '||coalesce(cn,'?')||': '||r.code||' x'||r.qty||' dihapus'); end if;
  return r;
end $$;
drop trigger if exists log_lines on order_lines;
create trigger log_lines after insert or update or delete on order_lines for each row execute function trg_log_lines();

-- ---------- barang ----------
create or replace function trg_log_items() returns trigger language plpgsql security definer set search_path = public, auth as $$
declare r items;
begin
  r := case when tg_op = 'DELETE' then old else new end;
  if tg_op = 'DELETE' and not exists (select 1 from trips where id = r.trip_id) then return old; end if;
  if tg_op = 'INSERT' then perform log_act(r.shop_id,'barang','Barang '||r.code||' '||r.name||' ditambahkan');
  elsif tg_op = 'UPDATE' then
    if new.price is distinct from old.price then perform log_act(r.shop_id,'barang','Harga toko '||r.code||' diubah dari '||trim_scale(old.price)||' menjadi '||trim_scale(new.price)); end if;
    if new.status is distinct from old.status then perform log_act(r.shop_id,'barang','Barang '||r.code||case new.status when 'dibeli' then ' ditandai sudah dibeli' when 'habis' then ' ditandai habis' else ' dikembalikan ke belum dibeli' end); end if;
  else perform log_act(r.shop_id,'barang','Barang '||r.code||' '||r.name||' dihapus'); end if;
  return r;
end $$;
drop trigger if exists log_items on items;
create trigger log_items after insert or update or delete on items for each row execute function trg_log_items();

-- ---------- trip ----------
create or replace function trg_log_trips() returns trigger language plpgsql security definer set search_path = public, auth as $$
begin
  if tg_op = 'INSERT' then perform log_act(new.shop_id,'trip','Trip '||new.name||' dibuat');
  elsif tg_op = 'UPDATE' then
    if new.name is distinct from old.name then perform log_act(new.shop_id,'trip','Trip '||old.name||' diganti nama menjadi '||new.name); end if;
  else perform log_act(old.shop_id,'trip','Trip '||old.name||' dihapus'); end if;
  return coalesce(new, old);
end $$;
drop trigger if exists log_trips on trips;
create trigger log_trips after insert or update or delete on trips for each row execute function trg_log_trips();

-- ---------- fee dan kurs ----------
create or replace function trg_log_pricing() returns trigger language plpgsql security definer set search_path = public, auth as $$
declare tn text;
begin
  if tg_op = 'UPDATE' and (new.rate, new.fee_pct, new.fee_flat, new.round_to, new.extra_cost)
     is distinct from (old.rate, old.fee_pct, old.fee_flat, old.round_to, old.extra_cost) then
    select name into tn from trips where id = new.trip_id;
    perform log_act(new.shop_id,'harga','Harga trip '||coalesce(tn,'')||' diubah: kurs '||coalesce(new.rate,0)||', fee '||coalesce(new.fee_pct,0)||'% + '||fmt_rp(new.fee_flat)||', biaya lain '||fmt_rp(new.extra_cost));
  end if;
  return new;
end $$;
drop trigger if exists log_pricing on trip_pricing;
create trigger log_pricing after update on trip_pricing for each row execute function trg_log_pricing();

-- ---------- pelanggan ----------
create or replace function trg_log_customers() returns trigger language plpgsql security definer set search_path = public, auth as $$
begin
  perform log_act(old.shop_id,'pelanggan','Pelanggan '||old.name||' dihapus');
  return old;
end $$;
drop trigger if exists log_customers on customers;
create trigger log_customers after delete on customers for each row execute function trg_log_customers();

-- ---------- anggota ----------
create or replace function trg_log_members() returns trigger language plpgsql security definer set search_path = public, auth as $$
declare r members; nm text;
begin
  r := case when tg_op = 'DELETE' then old else new end;
  if tg_op = 'DELETE' and not exists (select 1 from shops where id = r.shop_id) then return old; end if;
  select coalesce(nullif(r.name,''), u.email, 'anggota') into nm from auth.users u where u.id = r.user_id;
  if tg_op = 'INSERT' then perform log_act(r.shop_id,'anggota',coalesce(nm,'anggota')||' ditambahkan sebagai '||r.role);
  elsif tg_op = 'UPDATE' then
    if new.role is distinct from old.role then perform log_act(r.shop_id,'anggota',coalesce(nm,'anggota')||' diubah dari '||old.role||' menjadi '||new.role); end if;
  else perform log_act(r.shop_id,'anggota',coalesce(nm,'anggota')||' dikeluarkan'); end if;
  return r;
end $$;
drop trigger if exists log_members on members;
create trigger log_members after insert or update or delete on members for each row execute function trg_log_members();
