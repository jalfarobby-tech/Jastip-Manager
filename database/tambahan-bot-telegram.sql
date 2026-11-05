-- Ringkasan harian untuk bot Telegram. Jalankan sekali di Supabase (SQL Editor).
-- GANTI 'ganti-dengan-kata-sandi-panjangmu' dengan kata sandi buatanmu sendiri (minimal 16 karakter),
-- lalu simpan kata sandi yang sama sebagai secret GitHub bernama BOT_KUNCI.
create table if not exists bot_config (name text primary key, value text not null);
alter table bot_config enable row level security;   -- tanpa policy: tidak bisa dibaca dari aplikasi
insert into bot_config(name, value) values ('kunci', 'ganti-dengan-kata-sandi-panjangmu')
  on conflict (name) do update set value = excluded.value;

create or replace function bot_ringkasan(p_kunci text) returns json
language plpgsql security definer set search_path = public as $$
begin
  if p_kunci is null or p_kunci is distinct from (select value from bot_config where name = 'kunci') then
    raise exception 'kunci salah' using errcode = '28000';
  end if;
  return coalesce((
    select json_agg(x order by x.deadline nulls last) from (
      select t.name as trip, t.deadline as deadline,
        (select count(distinct o.customer_id) from order_lines o where o.trip_id = t.id and not o.cancelled)::int as pelanggan,
        (select count(distinct o.customer_id) from order_lines o where o.trip_id = t.id and not o.cancelled
           and not exists (select 1 from payments p where p.trip_id = t.id and p.customer_id = o.customer_id))::int as belum_bayar,
        (select count(distinct i.id) from items i where i.trip_id = t.id and i.status = 'belum'
           and exists (select 1 from order_lines o where o.trip_id = t.id and o.code = i.code and not o.cancelled and coalesce(o.released, true)))::int as belum_dibeli,
        (select coalesce(sum(p.amount), 0) from payments p where p.trip_id = t.id)::bigint as uang_masuk
      from trips t
      where t.deadline is null or t.deadline >= current_date - 14
    ) x
  ), '[]'::json);
end $$;
revoke all on function bot_ringkasan(text) from public;
grant execute on function bot_ringkasan(text) to anon, authenticated;
notify pgrst, 'reload schema';
