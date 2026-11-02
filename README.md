# Jastip Manager

Aplikasi pencatat jastip: barang, pesanan (termasuk impor chat WhatsApp), daftar belanja, tagihan, dan untung.
Dua halaman, tanpa proses build: `index.html` (halaman depan sebelum login) dan `app.html` (aplikasinya). Data disimpan di Supabase, login dengan email.

## Peran
- **Pemilik**: melihat semua, termasuk kurs, modal, dan untung. Mengelola anggota.
- **Pencatat**: mencatat barang, pesanan, pembayaran. Tidak bisa melihat kurs, modal, atau untung.
- **Pembeli**: hanya daftar belanja dan menandai barang yang sudah dibeli.

## Pasang (sekali saja)

### 1. Database
Di Supabase buka **SQL Editor > New query**. Kalau `schema.sql` lama sudah pernah dijalankan, cukup jalankan
`database/tambahan-import-log.sql` lalu `database/tambahan-pengiriman.sql` (status pengiriman dan info pembayaran), lalu `database/tambahan-optimasi.sql` dan `database/tambahan-optimasi-2.sql` (indeks, RLS ringan, Realtime). Kalau belum, jalankan `database/schema-lengkap.sql` (sudah termasuk tambahan itu).

### 2. GitHub Pages
1. Buat repo baru (public), misalnya `jastip`.
2. Upload `index.html`, `app.html`, `manifest.webmanifest`, `icon.svg`, `icon-192.png`, `icon-512.png` ke root repo.
3. **Settings > Pages > Build and deployment > Source: Deploy from a branch**, pilih `main` dan `/ (root)`, lalu Save.
4. Tunggu sekitar satu menit. Alamatnya `https://USERNAME.github.io/jastip/`.

### 3. Supabase
- **Authentication > URL Configuration**: isi **Site URL** dengan alamat GitHub Pages tadi.
- **Authentication > Providers > Email**: matikan **Confirm email** supaya karyawan bisa langsung masuk setelah daftar
  (kalau dibiarkan menyala, setiap akun baru harus klik tautan di emailnya dulu).

## Pemakaian pertama
1. Buka alamat aplikasi, **Daftar** dengan email pemilik, lalu **Buat toko**.
2. Buat trip (kurs, fee, pembulatan), tambah barang, lalu impor chat grup WhatsApp.
3. Karyawan daftar sendiri di alamat yang sama. Pemilik buka **Pengaturan > Anggota**, masukkan email karyawan, pilih perannya.

## Catatan
- Kunci di dalam `app.html` adalah anon key yang memang publik. Jangan pernah memasukkan `service_role`/secret key atau password database ke repo.
- Supabase gratis menjeda proyek yang tidak dipakai satu minggu. Buka aplikasi sesekali, atau aktifkan lagi lewat dashboard.
- Paket gratis tidak punya cadangan otomatis. Ekspor data berkala dari dashboard Supabase.
- Pencatat memasukkan harga toko dan bisa menaksir modal kalau tahu kurs pasar. Kalau ingin lebih ketat, jadikan input harga khusus pemilik.

## Hemat kuota Supabase
- Aplikasi hanya mengunduh data trip yang sedang dibuka. Barang, pesanan, dan pembayaran trip lama tidak ikut terunduh.
- Perubahan dari HP lain datang lewat Realtime, dan hanya tabel yang berubah yang dimuat ulang. Pemeriksaan berkala hanya cadangan (tiap 3 menit saat Realtime tersambung).
- Proyek Supabase gratis dijeda kalau 7 hari tidak ada aktivitas. Buka aplikasi sesekali, atau minta file `keepalive.yml` opsional.
