-- Tambahan untuk versi online: catatan chat WhatsApp yang sudah diimpor (supaya impor ulang tidak dobel).
-- Jalankan sekali di Supabase: SQL Editor > New query > tempel > Run.
create table if not exists import_log (
  shop_id uuid not null references shops(id) on delete cascade,
  hash    text not null,
  primary key (shop_id, hash)
);
alter table import_log enable row level security;
drop policy if exists import_log_all on import_log;
create policy import_log_all on import_log for all
  using (has_role(shop_id, array['owner','pencatat']::member_role[]))
  with check (has_role(shop_id, array['owner','pencatat']::member_role[]));
revoke all on import_log from anon;
grant select, insert, update, delete on import_log to authenticated;
