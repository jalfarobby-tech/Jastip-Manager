-- Jalankan sekali di Supabase > SQL Editor. Aman diulang.
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

notify pgrst, 'reload schema';
