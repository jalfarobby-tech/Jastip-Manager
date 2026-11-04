-- HARGA JUAL BEBAS PER BARANG
-- Selain otomatis (kurs + fee trip), pencatat dan owner bisa mengisi harga jual sendiri per barang (mis. modal 100.000, jual 150.000).
-- Tempel di Supabase > SQL Editor > New query, lalu Run. Aman diulang.

alter table items add column if not exists sell_fixed numeric(14,0);   -- kosong = otomatis

create or replace function items_set_sell_price() returns trigger
language plpgsql security definer set search_path = public as $$
declare tp trip_pricing;
begin
  if new.sell_fixed is not null then
    new.sell_price := new.sell_fixed;
    return new;
  end if;
  select * into tp from trip_pricing where trip_id = new.trip_id;
  if found then
    new.sell_price := ceil((new.price * tp.rate * (1 + tp.fee_pct/100) + tp.fee_flat) / tp.round_to - 0.000001) * tp.round_to;
  else
    new.sell_price := null;
  end if;
  return new;
end $$;

drop trigger if exists items_price on items;
create trigger items_price before insert or update of price, trip_id, sell_fixed on items
  for each row execute function items_set_sell_price();

-- petugas belanja tidak boleh mengubah harga jual
create or replace function items_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if has_role(old.shop_id, array['pembeli']::member_role[])
     and (new.code <> old.code or new.name <> old.name or new.price <> old.price
          or new.store is distinct from old.store or new.stock_cap is distinct from old.stock_cap
          or new.trip_id <> old.trip_id or new.sell_fixed is distinct from old.sell_fixed) then
    raise exception 'pembeli hanya boleh mengubah status pembelian';
  end if;
  return new;
end $$;

notify pgrst, 'reload schema';
