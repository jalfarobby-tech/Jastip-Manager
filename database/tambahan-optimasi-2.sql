-- Jalankan sekali di Supabase > SQL Editor, SETELAH tambahan-optimasi.sql. Aman diulang.
-- Cocok dengan aplikasi yang sekarang hanya memuat data trip yang sedang dibuka.

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
