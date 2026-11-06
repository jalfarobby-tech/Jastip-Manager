-- Akses tertutup: hanya admin yang membuat akun pemilik dan tokonya. Jalankan sekali di Supabase (SQL Editor).

-- 1. Pengguna biasa tidak boleh lagi membuat toko sendiri.
revoke execute on function create_shop(text) from public, anon, authenticated;

-- 2. Fungsi untuk admin (kamu): menghubungkan akun pemilik yang sudah dibuat di Authentication > Users ke tokonya.
create or replace function admin_buat_toko(p_email text, p_toko text) returns uuid
language plpgsql security definer set search_path = public as $$
declare u uuid; s uuid;
begin
  select id into u from auth.users where lower(email) = lower(p_email);
  if u is null then
    raise exception 'akun % belum dibuat di Authentication > Users', p_email;
  end if;
  insert into shops(name) values (p_toko) returning id into s;
  insert into members(shop_id, user_id, role) values (s, u, 'owner');
  return s;
end $$;
revoke all on function admin_buat_toko(text, text) from public, anon, authenticated;

notify pgrst, 'reload schema';

-- Cara memakai (jalankan terpisah, setelah akun pemilik dibuat di Authentication > Users > Add user,
-- dengan "Auto Confirm User" dicentang):
--   select admin_buat_toko('email-pemilik@gmail.com', 'Nama Toko Pemilik');
