-- GABUNGAN: pengiriman + optimasi + optimasi-2. Tempel semuanya di Supabase > SQL Editor > New query, lalu tekan Run satu kali.
-- Aman diulang berapa kali pun. Syarat: schema dasar (tabel shops, trips, items, dst.) sudah pernah dijalankan.

-- ===== 1) Pengiriman dan info pembayaran =====
alter table shops add column if not exists pay_info text;

create table if not exists deliveries (
  id          uuid primary key default gen_random_uuid(),
  shop_id     uuid not null references shops(id) on delete cascade,
  trip_id     uuid not null references trips(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete cascade,
  status      text not null check (status in ('told','packed','sent')),
  resi        text not null default '',
  unique (trip_id, customer_id)
);
alter table deliveries enable row level security;
drop policy if exists deliveries_all on deliveries;
create policy deliveries_all on deliveries for all
  using (has_role(shop_id, array['owner','pencatat']::member_role[]))
  with check (has_role(shop_id, array['owner','pencatat']::member_role[]));

drop policy if exists shops_owner_upd on shops;
create policy shops_owner_upd on shops for update
  using (has_role(id, array['owner']::member_role[])) with check (has_role(id, array['owner']::member_role[]));


-- ===== 2) Optimasi: indeks, RLS ringan, Realtime =====
-- 1) indeks shop_id (hampir semua query dan aturan RLS memfilter dengannya)
-- 2) aturan RLS: fungsi akses dibungkus (select ...) agar dihitung sekali per query, bukan per baris
-- 3) aktifkan Realtime untuk tabel yang dipantau aplikasi

-- ---------- 1) indeks ----------
create index if not exists trips_shop_idx          on trips (shop_id);
create index if not exists trip_pricing_shop_idx   on trip_pricing (shop_id);
create index if not exists items_shop_idx          on items (shop_id);
create index if not exists item_purchases_shop_idx on item_purchases (shop_id);
create index if not exists customers_shop_idx      on customers (shop_id);
create index if not exists order_lines_shop_idx    on order_lines (shop_id);
create index if not exists payments_shop_idx       on payments (shop_id);
create index if not exists deliveries_shop_idx     on deliveries (shop_id);
create index if not exists members_shop_idx        on members (shop_id, user_id);

-- ---------- 2) RLS lebih ringan (hasil akses sama persis) ----------
alter policy shops_read    on shops   using ((select is_member(id)));
alter policy members_read  on members using (user_id = (select auth.uid()) or (select has_role(shop_id, array['owner']::member_role[])));
alter policy members_owner on members
  using ((select has_role(shop_id, array['owner']::member_role[])))
  with check ((select has_role(shop_id, array['owner']::member_role[])));
alter policy trips_read    on trips   using ((select is_member(shop_id)));
alter policy trips_owner   on trips
  using ((select has_role(shop_id, array['owner']::member_role[])))
  with check ((select has_role(shop_id, array['owner']::member_role[])));
alter policy pricing_owner on trip_pricing
  using ((select has_role(shop_id, array['owner']::member_role[])))
  with check ((select has_role(shop_id, array['owner']::member_role[])));
alter policy items_read    on items   using ((select is_member(shop_id)));
alter policy items_ins     on items   with check ((select has_role(shop_id, array['owner','pencatat']::member_role[])));
alter policy items_upd     on items
  using ((select has_role(shop_id, array['owner','pencatat','pembeli']::member_role[])))
  with check ((select has_role(shop_id, array['owner','pencatat','pembeli']::member_role[])));
alter policy items_del     on items   using ((select has_role(shop_id, array['owner','pencatat']::member_role[])));
alter policy purchases_all on item_purchases
  using ((select has_role(shop_id, array['owner','pembeli']::member_role[])))
  with check ((select has_role(shop_id, array['owner','pembeli']::member_role[])));
alter policy customers_all on customers
  using ((select has_role(shop_id, array['owner','pencatat']::member_role[])))
  with check ((select has_role(shop_id, array['owner','pencatat']::member_role[])));
alter policy lines_all     on order_lines
  using ((select has_role(shop_id, array['owner','pencatat']::member_role[])))
  with check ((select has_role(shop_id, array['owner','pencatat']::member_role[])));
alter policy payments_all  on payments
  using ((select has_role(shop_id, array['owner','pencatat']::member_role[])))
  with check ((select has_role(shop_id, array['owner','pencatat']::member_role[])));
alter policy import_log_all on import_log
  using ((select has_role(shop_id, array['owner','pencatat']::member_role[])))
  with check ((select has_role(shop_id, array['owner','pencatat']::member_role[])));
alter policy deliveries_all on deliveries
  using ((select has_role(shop_id, array['owner','pencatat']::member_role[])))
  with check ((select has_role(shop_id, array['owner','pencatat']::member_role[])));
alter policy shops_owner_upd on shops
  using ((select has_role(id, array['owner']::member_role[])))
  with check ((select has_role(id, array['owner']::member_role[])));

-- ---------- 3) Realtime ----------
do $$
declare t text;
begin
  foreach t in array array['trips','items','customers','order_lines','payments','deliveries'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;


-- ===== 3) Optimasi lanjutan =====

-- Kunci asing yang belum punya indeks: tanpa ini, menghapus pelanggan memindai seluruh tabel anak.
create index if not exists payments_customer_idx   on payments (customer_id);
create index if not exists deliveries_customer_idx on deliveries (customer_id);
create index if not exists order_lines_customer_idx on order_lines (customer_id);

-- Perubahan harga/kurs trip juga dikabarkan lewat Realtime (aplikasi memuat ulang daftar trip saja).
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname='supabase_realtime' and schemaname='public' and tablename='trip_pricing') then
    alter publication supabase_realtime add table public.trip_pricing;
  end if;
end $$;

-- Perbarui statistik supaya perencana query memakai indeks dengan benar.
analyze trips; analyze items; analyze order_lines; analyze payments; analyze deliveries; analyze customers;

notify pgrst, 'reload schema';


-- ===== 4) Bayar dulu, baru belanja =====
-- Pesanan baru baru tampil di daftar belanja petugas setelah pelanggan lunas (dikonfirmasi pencatat).
-- Pesanan lama otomatis dianggap sudah dibayar (default true), jadi daftar belanja yang sudah ada tidak berubah.

alter table order_lines add column if not exists released boolean not null default true;

create or replace function shopping_list(p_trip uuid)
returns table (item_id uuid, code text, name text, store text, price numeric, status text, bought_qty integer, ordered_qty integer)
language sql stable security definer set search_path = public as $$
  select i.id, i.code, i.name, i.store, i.price, i.status, i.bought_qty,
         coalesce(sum(l.qty) filter (where not l.cancelled and l.released), 0)::int
  from items i
  left join order_lines l on l.trip_id = i.trip_id and l.code = i.code
  where i.trip_id = p_trip and is_member(i.shop_id)
  group by i.id;
$$;


notify pgrst, 'reload schema';


-- ===== 5) Harga jual bebas per barang =====
-- Selain otomatis (kurs + fee trip), pencatat dan owner bisa mengisi harga jual sendiri per barang (mis. modal 100.000, jual 150.000).

alter table items add column if not exists sell_fixed numeric(14,0);   -- kosong = otomatis

create or replace function items_set_sell_price() returns trigger
language plpgsql security definer set search_path = public as $$
declare tp trip_pricing;
begin
  if new.sell_fixed is not null then
    new.sell_price := new.sell_fixed;
    return new;
  end if;
  select * into tp from trip_pricing where trip_id = new.trip_id;
  if found then
    new.sell_price := ceil((new.price * tp.rate * (1 + tp.fee_pct/100) + tp.fee_flat) / tp.round_to - 0.000001) * tp.round_to;
  else
    new.sell_price := null;
  end if;
  return new;
end $$;

drop trigger if exists items_price on items;
create trigger items_price before insert or update of price, trip_id, sell_fixed on items
  for each row execute function items_set_sell_price();

-- petugas belanja tidak boleh mengubah harga jual
create or replace function items_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if has_role(old.shop_id, array['pembeli']::member_role[])
     and (new.code <> old.code or new.name <> old.name or new.price <> old.price
          or new.store is distinct from old.store or new.stock_cap is distinct from old.stock_cap
          or new.trip_id <> old.trip_id or new.sell_fixed is distinct from old.sell_fixed) then
    raise exception 'pembeli hanya boleh mengubah status pembelian';
  end if;
  return new;
end $$;

notify pgrst, 'reload schema';
