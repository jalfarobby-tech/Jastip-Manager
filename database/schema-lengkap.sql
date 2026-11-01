-- Jastip Manager: skema Supabase (Postgres)
-- Satu "toko" = satu pelanggan SaaS. Semua tabel membawa shop_id dan Row Level Security (RLS)
-- membatasi tiap pengguna ke toko serta perannya.
--
-- Pembagian data per peran:
--   owner     : semua, termasuk kurs, fee, modal sebenarnya, dan untung
--   pencatat  : barang, pesanan, pelanggan, pembayaran. TIDAK bisa membaca kurs, fee, biaya lain, atau harga beli sebenarnya
--   pembeli   : daftar belanja dan mencatat pembelian. TIDAK bisa membaca pelanggan, pesanan, atau uang
--
-- Catatan jujur: pencatat yang memasukkan harga toko dan tahu kurs pasar bisa menebak modalnya.
-- Kalau ingin lebih rapat, jadikan input harga barang khusus owner (ubah policy items_ins/items_upd).
--
-- Jalankan di Supabase: SQL Editor > New query > tempel > Run.

-- ---------- toko & anggota ----------
create table shops (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  created_at timestamptz not null default now()
);

create type member_role as enum ('owner','pencatat','pembeli');

create table members (
  shop_id uuid not null references shops(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role    member_role not null default 'pencatat',
  name    text,
  primary key (shop_id, user_id)
);

-- security definer supaya tidak rekursif lewat RLS tabel members
create function is_member(s uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from members where shop_id = s and user_id = auth.uid());
$$;

create function has_role(s uuid, r member_role[]) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from members where shop_id = s and user_id = auth.uid() and role = any(r));
$$;

-- ---------- trip ----------
create table trips (
  id         uuid primary key default gen_random_uuid(),
  shop_id    uuid not null references shops(id) on delete cascade,
  name       text not null,
  currency   text not null default 'KRW',
  deadline   date,
  created_at timestamptz not null default now()
);

-- Rumus harga & biaya: HANYA owner yang bisa membaca atau mengubah
create table trip_pricing (
  trip_id    uuid primary key references trips(id) on delete cascade,
  shop_id    uuid not null references shops(id) on delete cascade,
  rate       numeric(18,6) not null check (rate > 0),     -- Rp per 1 mata uang
  fee_pct    numeric(6,2)  not null default 0,
  fee_flat   numeric(14,0) not null default 0,
  round_to   numeric(10,0) not null default 1 check (round_to >= 1),
  extra_cost numeric(14,0) not null default 0              -- ongkir, pajak, dll
);

-- ---------- barang ----------
create table items (
  id         uuid primary key default gen_random_uuid(),
  shop_id    uuid not null references shops(id) on delete cascade,
  trip_id    uuid not null references trips(id) on delete cascade,
  code       text not null,                               -- huruf besar tanpa simbol
  name       text not null,
  store      text,
  price      numeric(18,2) not null check (price >= 0),   -- harga di toko (mata uang lokal)
  sell_price numeric(14,0),                               -- harga jual (Rp), dihitung otomatis oleh trigger
  stock_cap  integer check (stock_cap >= 0),
  status     text not null default 'belum' check (status in ('belum','dibeli','habis')),
  bought_qty integer check (bought_qty >= 0),
  unique (trip_id, code)
);

-- Harga beli sebenarnya: hanya owner dan pembeli
create table item_purchases (
  item_id      uuid primary key references items(id) on delete cascade,
  shop_id      uuid not null references shops(id) on delete cascade,
  actual_price numeric(18,2) not null check (actual_price >= 0),
  buyer_id     uuid references auth.users(id),
  bought_at    timestamptz not null default now()
);

-- harga jual dihitung di server dari trip_pricing, jadi pencatat tidak perlu (dan tidak bisa) membaca rumusnya
create function items_set_sell_price() returns trigger
language plpgsql security definer set search_path = public as $$
declare tp trip_pricing;
begin
  select * into tp from trip_pricing where trip_id = new.trip_id;
  if found then
    new.sell_price := ceil((new.price * tp.rate * (1 + tp.fee_pct/100) + tp.fee_flat) / tp.round_to - 0.000001) * tp.round_to;
  end if;
  return new;
end $$;

create trigger items_price before insert or update of price, trip_id on items
  for each row execute function items_set_sell_price();

-- kalau owner mengubah kurs/fee, hitung ulang semua harga jual trip itu
create function pricing_changed() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update items set price = price where trip_id = new.trip_id;
  return new;
end $$;

create trigger pricing_recalc after insert or update on trip_pricing
  for each row execute function pricing_changed();

-- pembeli hanya boleh mengubah status pembelian, bukan data barang lain
create function items_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if has_role(old.shop_id, array['pembeli']::member_role[])
     and (new.code <> old.code or new.name <> old.name or new.price <> old.price
          or new.store is distinct from old.store or new.stock_cap is distinct from old.stock_cap
          or new.trip_id <> old.trip_id) then
    raise exception 'pembeli hanya boleh mengubah status pembelian';
  end if;
  return new;
end $$;

create trigger items_guard_t before update on items
  for each row execute function items_guard();

-- ---------- pelanggan, pesanan, pembayaran ----------
create table customers (
  id      uuid primary key default gen_random_uuid(),
  shop_id uuid not null references shops(id) on delete cascade,
  name    text not null,
  phone   text,
  unique (shop_id, name)
);

-- Pesanan menyimpan kode (bukan item_id) supaya boleh masuk sebelum barangnya diposting,
-- lalu tersambung otomatis ketika barang dengan kode itu dibuat.
create table order_lines (
  id          uuid primary key default gen_random_uuid(),
  shop_id     uuid not null references shops(id) on delete cascade,
  trip_id     uuid not null references trips(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete cascade,
  code        text not null,
  qty         integer not null check (qty > 0),
  ordered_at  timestamptz not null default now(),         -- urutan siapa cepat dapat
  cancelled   boolean not null default false,
  source      text not null default 'manual',
  import_hash text,
  unique (shop_id, import_hash)                           -- mencegah chat yang sama masuk dua kali
);

create table payments (
  id          uuid primary key default gen_random_uuid(),
  shop_id     uuid not null references shops(id) on delete cascade,
  trip_id     uuid not null references trips(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete cascade,
  amount      numeric(14,0) not null check (amount > 0),
  note        text,
  paid_at     timestamptz not null default now()
);

create index on items (trip_id);
create index on order_lines (trip_id, code, ordered_at);
create index on order_lines (customer_id);
create index on payments (trip_id, customer_id);
create index on members (user_id);

-- ---------- Row Level Security ----------
alter table shops          enable row level security;
alter table members        enable row level security;
alter table trips          enable row level security;
alter table trip_pricing   enable row level security;
alter table items          enable row level security;
alter table item_purchases enable row level security;
alter table customers      enable row level security;
alter table order_lines    enable row level security;
alter table payments       enable row level security;

create policy shops_read on shops for select using (is_member(id));

create policy members_read on members for select
  using (user_id = auth.uid() or has_role(shop_id, array['owner']::member_role[]));
create policy members_owner on members for all
  using (has_role(shop_id, array['owner']::member_role[]))
  with check (has_role(shop_id, array['owner']::member_role[]));

create policy trips_read on trips for select using (is_member(shop_id));
create policy trips_owner on trips for all
  using (has_role(shop_id, array['owner']::member_role[]))
  with check (has_role(shop_id, array['owner']::member_role[]));

create policy pricing_owner on trip_pricing for all
  using (has_role(shop_id, array['owner']::member_role[]))
  with check (has_role(shop_id, array['owner']::member_role[]));

-- barang: semua anggota membaca; owner & pencatat menambah/mengubah; pembeli hanya mengubah status
create policy items_read on items for select using (is_member(shop_id));
create policy items_ins  on items for insert
  with check (has_role(shop_id, array['owner','pencatat']::member_role[]));
create policy items_upd  on items for update
  using (has_role(shop_id, array['owner','pencatat','pembeli']::member_role[]))
  with check (has_role(shop_id, array['owner','pencatat','pembeli']::member_role[]));
create policy items_del  on items for delete
  using (has_role(shop_id, array['owner','pencatat']::member_role[]));

create policy purchases_all on item_purchases for all
  using (has_role(shop_id, array['owner','pembeli']::member_role[]))
  with check (has_role(shop_id, array['owner','pembeli']::member_role[]));

create policy customers_all on customers for all
  using (has_role(shop_id, array['owner','pencatat']::member_role[]))
  with check (has_role(shop_id, array['owner','pencatat']::member_role[]));
create policy lines_all on order_lines for all
  using (has_role(shop_id, array['owner','pencatat']::member_role[]))
  with check (has_role(shop_id, array['owner','pencatat']::member_role[]));
create policy payments_all on payments for all
  using (has_role(shop_id, array['owner','pencatat']::member_role[]))
  with check (has_role(shop_id, array['owner','pencatat']::member_role[]));

-- ---------- daftar belanja untuk pembeli ----------
-- Pembeli tidak boleh membaca order_lines. Fungsi ini hanya memberi total per kode.
create function shopping_list(p_trip uuid)
returns table (item_id uuid, code text, name text, store text, price numeric, status text, bought_qty integer, ordered_qty integer)
language sql stable security definer set search_path = public as $$
  select i.id, i.code, i.name, i.store, i.price, i.status, i.bought_qty,
         coalesce(sum(l.qty) filter (where not l.cancelled), 0)::int
  from items i
  left join order_lines l on l.trip_id = i.trip_id and l.code = i.code
  where i.trip_id = p_trip and is_member(i.shop_id)
  group by i.id;
$$;

-- ---------- membuat toko baru ----------
-- Dipanggil dari aplikasi setelah pengguna mendaftar: rpc('create_shop', {shop_name:'...'})
create function create_shop(shop_name text) returns uuid
language plpgsql security definer set search_path = public as $$
declare s uuid;
begin
  if auth.uid() is null then raise exception 'harus login'; end if;
  insert into shops(name) values (shop_name) returning id into s;
  insert into members(shop_id, user_id, role) values (s, auth.uid(), 'owner');
  return s;
end $$;

-- ---------- kelola anggota (hanya owner) ----------
-- Karyawan mendaftar sendiri di aplikasi dengan emailnya. Setelah itu owner memasukkan email itu
-- dan memilih perannya: rpc('add_member', {p_shop:'...', p_email:'a@b.com', p_role:'pencatat', p_name:'Dewi'})
create function add_member(p_shop uuid, p_email text, p_role member_role, p_name text default null) returns void
language plpgsql security definer set search_path = public as $$
declare u uuid;
begin
  if not has_role(p_shop, array['owner']::member_role[]) then
    raise exception 'hanya pemilik yang boleh menambah anggota';
  end if;
  select id into u from auth.users where lower(email) = lower(p_email);
  if u is null then
    raise exception 'email belum terdaftar, minta karyawan mendaftar dulu di aplikasi';
  end if;
  insert into members(shop_id, user_id, role, name) values (p_shop, u, p_role, p_name)
  on conflict (shop_id, user_id) do update set role = excluded.role, name = coalesce(excluded.name, members.name);
end $$;

create function remove_member(p_shop uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not has_role(p_shop, array['owner']::member_role[]) then
    raise exception 'hanya pemilik yang boleh menghapus anggota';
  end if;
  if p_user = auth.uid() then
    raise exception 'pemilik tidak bisa menghapus dirinya sendiri';
  end if;
  delete from members where shop_id = p_shop and user_id = p_user;
end $$;

-- ---------- catatan impor chat WhatsApp ----------
-- Dipakai versi online supaya chat yang sama tidak masuk dua kali.
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

-- ---------- izin akses ----------
-- Hanya pengguna yang sudah login (authenticated) yang boleh menyentuh tabel dan fungsi.
-- Pengunjung tanpa login (anon) tidak diberi akses apa pun. RLS di atas tetap membatasi barisnya.
revoke all on all tables    in schema public from anon;
revoke execute on all functions in schema public from public, anon;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;
