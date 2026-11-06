-- Akun baru yang kamu buat lewat Authentication > Users > Add user otomatis mendapat toko sendiri (sebagai pemilik).
-- Akun karyawan yang dibuat pemilik lewat aplikasi (Edge Function buat-karyawan) ditandai karyawan, jadi tidak dapat toko.
create or replace function auto_toko_pemilik() returns trigger
language plpgsql security definer set search_path = public as $$
declare s uuid;
begin
  if coalesce(new.raw_user_meta_data->>'karyawan', '') = 'true' then return new; end if;
  insert into shops(name) values ('Toko ' || split_part(new.email, '@', 1)) returning id into s;
  insert into members(shop_id, user_id, role) values (s, new.id, 'owner');
  return new;
exception when others then
  return new;   -- jangan pernah menggagalkan pembuatan akun
end $$;

drop trigger if exists auto_toko_pemilik on auth.users;
create trigger auto_toko_pemilik after insert on auth.users
  for each row execute function auto_toko_pemilik();
