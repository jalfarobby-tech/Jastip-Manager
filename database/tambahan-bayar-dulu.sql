-- BAYAR DULU, BARU BELANJA
-- Pesanan baru baru tampil di daftar belanja petugas setelah pelanggan lunas (dikonfirmasi pencatat).
-- Tempel di Supabase > SQL Editor > New query, lalu Run. Aman diulang.
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
