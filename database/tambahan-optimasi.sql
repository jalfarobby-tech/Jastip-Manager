-- Jalankan sekali di Supabase > SQL Editor. Aman diulang.
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

notify pgrst, 'reload schema';
