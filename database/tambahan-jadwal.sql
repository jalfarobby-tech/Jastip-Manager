-- Jastip Manager: kolom "perkiraan barang sampai" untuk setiap trip.
-- Aman dijalankan berulang. Tanpa ini aplikasi tetap jalan, hanya fitur perkiraan sampai yang tidak tampil.
alter table public.trips add column if not exists eta date;
