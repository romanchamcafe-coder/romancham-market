-- =====================================================================
--  ROMANCHAM MARKET — Supabase schema v1
--  Run once in Supabase SQL Editor (safe to re-run: drops & recreates functions,
--  uses IF NOT EXISTS for tables). No real business data or secrets in here.
-- =====================================================================
create extension if not exists pgcrypto;

-- ---------- helpers ----------
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at := now(); return new; end $$;

-- ---------- admins ----------
create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  email      text not null,
  role       text not null default 'owner' check (role in ('owner','manager','staff')),
  created_at timestamptz not null default now()
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- ---------- catalogue ----------
create table if not exists public.categories (
  slug        text primary key,
  name        text not null,
  description text,
  sort        int not null default 0,
  active      boolean not null default true
);

create table if not exists public.products (
  id            uuid primary key default gen_random_uuid(),
  sku           text unique not null,
  name          text not null,
  category_slug text not null references public.categories(slug) on update cascade,
  subcategory   text,
  short_desc    text,
  description   text,
  size_label    text,
  cocoa_pct     numeric(5,2),
  roast_level   text,
  origin        text,
  tasting_notes text,
  ingredients   text,
  allergens     text,
  shelf_life    text,
  storage       text,
  mrp           numeric(10,2) not null check (mrp >= 0),
  price         numeric(10,2) not null check (price >= 0),
  gst_rate      numeric(5,2)  not null default 5 check (gst_rate between 0 and 40),
  hsn           text,
  stock         int not null default 0 check (stock >= 0),
  low_stock_at  int not null default 5,
  image_url     text,
  is_bestseller boolean not null default false,
  is_gift       boolean not null default false,
  is_new        boolean not null default false,
  hamper_eligible boolean not null default true,
  is_sample     boolean not null default false,
  active        boolean not null default true,
  sort          int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint price_le_mrp check (price <= mrp)
);
create index if not exists products_cat_idx on public.products(category_slug) where active;
drop trigger if exists products_touch on public.products;
create trigger products_touch before update on public.products
  for each row execute function public.touch_updated_at();

create table if not exists public.inventory_movements (
  id         bigserial primary key,
  product_id uuid not null references public.products(id) on delete cascade,
  change     int not null,
  reason     text not null,          -- inward / outward / adjustment / order / cancel
  ref        text,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists inv_mov_product_idx on public.inventory_movements(product_id, created_at desc);

create table if not exists public.hamper_boxes (
  id       serial primary key,
  name     text not null,
  capacity int  not null check (capacity > 0),
  price    numeric(10,2) not null check (price >= 0),
  sort     int not null default 0,
  active   boolean not null default true
);

-- ---------- delivery & settings ----------
create table if not exists public.delivery_pincodes (
  pincode text primary key check (pincode ~ '^[0-9]{6}$'),
  area    text,
  charge  numeric(10,2) not null default 80,
  eta     text not null default '1–2 days',
  active  boolean not null default true
);

-- business_settings holds ONLY non-secret, publicly displayable values
create table if not exists public.business_settings (
  key   text primary key,
  value text
);

-- ---------- orders ----------
create sequence if not exists public.order_seq start 1001;

create table if not exists public.orders (
  id              uuid primary key default gen_random_uuid(),
  order_no        text unique not null,
  customer_name   text not null,
  phone           text not null,
  email           text,
  address         text not null,
  area            text,
  city            text not null default 'Chennai',
  state           text not null default 'Tamil Nadu',
  pincode         text not null,
  instructions    text,
  delivery_date   date,
  gift_message    text,
  recipient_name  text,
  sender_name     text,
  subtotal        numeric(10,2) not null,
  delivery_charge numeric(10,2) not null default 0,
  discount        numeric(10,2) not null default 0,
  total           numeric(10,2) not null,
  gst_included    numeric(10,2) not null default 0,
  payment_method  text not null default 'whatsapp',
  payment_status  text not null default 'pending'
                  check (payment_status in ('pending','paid','failed','refunded')),
  status          text not null default 'Pending'
                  check (status in ('Pending','Confirmed','Processing','Packed','Shipped',
                                    'Out for Delivery','Delivered','Cancelled','Refunded')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists orders_created_idx on public.orders(created_at desc);
create index if not exists orders_phone_idx on public.orders(phone);
drop trigger if exists orders_touch on public.orders;
create trigger orders_touch before update on public.orders
  for each row execute function public.touch_updated_at();

create table if not exists public.order_items (
  id          bigserial primary key,
  order_id    uuid not null references public.orders(id) on delete cascade,
  product_id  uuid references public.products(id) on delete set null,
  kind        text not null default 'product' check (kind in ('product','hamper')),
  name        text not null,
  sku         text,
  unit_price  numeric(10,2) not null,
  qty         int not null check (qty > 0),
  gst_rate    numeric(5,2) not null default 0,
  line_total  numeric(10,2) not null,
  components  jsonb
);
create index if not exists order_items_order_idx on public.order_items(order_id);

create table if not exists public.order_activity (
  id         bigserial primary key,
  order_id   uuid not null references public.orders(id) on delete cascade,
  action     text not null,
  note       text,
  actor      uuid,
  created_at timestamptz not null default now()
);

-- ---------- leads ----------
create table if not exists public.newsletter_subscribers (
  id         bigserial primary key,
  name       text,
  email      text not null,
  created_at timestamptz not null default now()
);
create unique index if not exists newsletter_email_uq on public.newsletter_subscribers (lower(email));

create table if not exists public.corporate_enquiries (
  id                bigserial primary key,
  company           text not null,
  contact_person    text not null,
  email             text not null,
  phone             text not null,
  quantity          int,
  budget_per_gift   numeric(10,2),
  delivery_date     date,
  delivery_location text,
  customisation     text,
  message           text,
  status            text not null default 'New'
                    check (status in ('New','Contacted','Quoted','Converted','Closed')),
  notes             text,
  created_at        timestamptz not null default now()
);

-- =====================================================================
--  ROW LEVEL SECURITY
-- =====================================================================
alter table public.admins                 enable row level security;
alter table public.categories             enable row level security;
alter table public.products               enable row level security;
alter table public.inventory_movements    enable row level security;
alter table public.hamper_boxes           enable row level security;
alter table public.delivery_pincodes      enable row level security;
alter table public.business_settings      enable row level security;
alter table public.orders                 enable row level security;
alter table public.order_items            enable row level security;
alter table public.order_activity         enable row level security;
alter table public.newsletter_subscribers enable row level security;
alter table public.corporate_enquiries    enable row level security;

do $$ declare t text; begin
  foreach t in array array['admins','categories','products','inventory_movements','hamper_boxes',
    'delivery_pincodes','business_settings','orders','order_items','order_activity',
    'newsletter_subscribers','corporate_enquiries'] loop
    execute format('drop policy if exists admin_all on public.%I', t);
    execute format('create policy admin_all on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

-- public read of the storefront data only
drop policy if exists public_read on public.categories;
create policy public_read on public.categories for select to anon, authenticated using (active);
drop policy if exists public_read on public.products;
create policy public_read on public.products for select to anon, authenticated using (active);
drop policy if exists public_read on public.hamper_boxes;
create policy public_read on public.hamper_boxes for select to anon, authenticated using (active);
drop policy if exists public_read on public.delivery_pincodes;
create policy public_read on public.delivery_pincodes for select to anon, authenticated using (active);
drop policy if exists public_read on public.business_settings;
create policy public_read on public.business_settings for select to anon, authenticated using (true);

-- corporate enquiries: public may only INSERT (never read)
drop policy if exists public_insert on public.corporate_enquiries;
create policy public_insert on public.corporate_enquiries for insert to anon, authenticated
  with check (status = 'New' and notes is null
              and length(company) between 1 and 200 and length(contact_person) between 1 and 120
              and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and phone ~ '^[0-9+ ]{8,15}$');

-- orders / items / newsletter: no direct public access at all → only through the RPCs below.

-- =====================================================================
--  RPCs (server-side logic: prices, stock, totals are computed HERE)
-- =====================================================================
drop function if exists public.place_order(jsonb, jsonb);
create or replace function public.place_order(p_items jsonb, p_customer jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_name text := trim(coalesce(p_customer->>'name',''));
  v_phone text := regexp_replace(coalesce(p_customer->>'phone',''), '[^0-9]', '', 'g');
  v_pin text := trim(coalesce(p_customer->>'pincode',''));
  v_addr text := trim(coalesce(p_customer->>'address',''));
  v_pin_row public.delivery_pincodes;
  v_item jsonb; v_comp jsonb;
  v_prod public.products; v_box public.hamper_boxes;
  v_qty int; v_cqty int; v_count int;
  v_sub numeric := 0; v_gst numeric := 0; v_line numeric; v_unit numeric;
  v_free numeric; v_del numeric; v_order_id uuid; v_order_no text;
  v_lines jsonb := '[]'::jsonb; v_comps jsonb;
  v_date date := nullif(p_customer->>'delivery_date','')::date;
begin
  if length(v_phone) = 12 and left(v_phone,2) = '91' then v_phone := right(v_phone,10); end if;
  if length(v_name) < 2 or length(v_name) > 120 then raise exception 'Please enter your name'; end if;
  if v_phone !~ '^[6-9][0-9]{9}$' then raise exception 'Please enter a valid 10-digit mobile number'; end if;
  if length(v_addr) < 8 then raise exception 'Please enter the full delivery address'; end if;
  select * into v_pin_row from public.delivery_pincodes where pincode = v_pin and active;
  if not found then raise exception 'Sorry, we do not deliver to pincode % yet', v_pin; end if;
  if v_date is not null and v_date < current_date then raise exception 'Delivery date cannot be in the past'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Your cart is empty'; end if;
  if jsonb_array_length(p_items) > 40 then raise exception 'Too many items in one order'; end if;

  -- simple abuse guard: max 5 orders per phone per 10 minutes
  select count(*) into v_count from public.orders where phone = v_phone and created_at > now() - interval '10 minutes';
  if v_count >= 5 then raise exception 'Too many orders in a short time — please WhatsApp us'; end if;

  v_order_no := 'RM' || to_char(now() at time zone 'Asia/Kolkata','YYMMDD') || '-' || nextval('public.order_seq');
  insert into public.orders(order_no, customer_name, phone, email, address, area, city, state, pincode,
     instructions, delivery_date, gift_message, recipient_name, sender_name, subtotal, total)
  values (v_order_no, v_name, v_phone, nullif(trim(p_customer->>'email'),''), v_addr,
     nullif(trim(p_customer->>'area'),''), coalesce(nullif(trim(p_customer->>'city'),''),'Chennai'), 'Tamil Nadu', v_pin,
     left(nullif(trim(p_customer->>'instructions'),''),500), v_date,
     left(nullif(trim(p_customer->>'gift_message'),''),300),
     left(nullif(trim(p_customer->>'recipient_name'),''),120), left(nullif(trim(p_customer->>'sender_name'),''),120), 0, 0)
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := coalesce((v_item->>'qty')::int, 0);
    if v_qty < 1 or v_qty > 50 then raise exception 'Invalid quantity'; end if;

    if coalesce(v_item->>'kind','product') = 'hamper' then
      select * into v_box from public.hamper_boxes where id = (v_item->>'box_id')::int and active;
      if not found then raise exception 'Hamper box not available'; end if;
      v_unit := v_box.price; v_count := 0; v_comps := '[]'::jsonb; v_gst := v_gst + 0;
      for v_comp in select * from jsonb_array_elements(coalesce(v_item->'components','[]'::jsonb)) loop
        v_cqty := coalesce((v_comp->>'qty')::int,0);
        if v_cqty < 1 then raise exception 'Invalid hamper item'; end if;
        select * into v_prod from public.products where id = (v_comp->>'product_id')::uuid and active and hamper_eligible for update;
        if not found then raise exception 'A hamper item is no longer available'; end if;
        if v_prod.stock < v_cqty * v_qty then raise exception 'Only % left of %', v_prod.stock, v_prod.name; end if;
        update public.products set stock = stock - v_cqty * v_qty where id = v_prod.id;
        insert into public.inventory_movements(product_id, change, reason, ref) values (v_prod.id, -(v_cqty*v_qty), 'order', v_order_no);
        v_count := v_count + v_cqty;
        v_unit := v_unit + v_prod.price * v_cqty;
        v_gst := v_gst + (v_prod.price * v_cqty * v_qty) * v_prod.gst_rate / (100 + v_prod.gst_rate);
        v_comps := v_comps || jsonb_build_object('product_id', v_prod.id, 'name', v_prod.name, 'qty', v_cqty, 'price', v_prod.price);
      end loop;
      if v_count = 0 then raise exception 'Your hamper is empty'; end if;
      if v_count > v_box.capacity then raise exception 'The % box holds only % items', v_box.name, v_box.capacity; end if;
      v_line := v_unit * v_qty;
      insert into public.order_items(order_id, kind, name, unit_price, qty, line_total, components)
        values (v_order_id, 'hamper', 'Custom Hamper — ' || v_box.name, v_unit, v_qty, v_line, v_comps);
      v_lines := v_lines || jsonb_build_object('name','Custom Hamper — '||v_box.name,'qty',v_qty,'unit',v_unit,'line',v_line,'components',v_comps);
    else
      select * into v_prod from public.products where id = (v_item->>'product_id')::uuid and active for update;
      if not found then raise exception 'A product in your cart is no longer available'; end if;
      if v_prod.stock < v_qty then raise exception 'Only % left of %', v_prod.stock, v_prod.name; end if;
      update public.products set stock = stock - v_qty where id = v_prod.id;
      insert into public.inventory_movements(product_id, change, reason, ref) values (v_prod.id, -v_qty, 'order', v_order_no);
      v_line := v_prod.price * v_qty;
      v_gst := v_gst + v_line * v_prod.gst_rate / (100 + v_prod.gst_rate);
      insert into public.order_items(order_id, product_id, name, sku, unit_price, qty, gst_rate, line_total)
        values (v_order_id, v_prod.id, v_prod.name, v_prod.sku, v_prod.price, v_qty, v_prod.gst_rate, v_line);
      v_lines := v_lines || jsonb_build_object('name',v_prod.name,'size',v_prod.size_label,'qty',v_qty,'unit',v_prod.price,'line',v_line);
    end if;
    v_sub := v_sub + v_line;
  end loop;

  select coalesce(nullif(value,'')::numeric, 999) into v_free from public.business_settings where key = 'free_shipping_threshold';
  v_free := coalesce(v_free, 999);
  v_del := case when v_sub >= v_free then 0 else v_pin_row.charge end;

  update public.orders set subtotal = v_sub, delivery_charge = v_del, total = v_sub + v_del,
         gst_included = round(v_gst, 2) where id = v_order_id;
  insert into public.order_activity(order_id, action, note) values (v_order_id, 'created', 'Order placed on website (awaiting confirmation)');

  return jsonb_build_object('order_no', v_order_no, 'subtotal', v_sub, 'delivery', v_del,
                            'total', v_sub + v_del, 'gst_included', round(v_gst,2), 'items', v_lines,
                            'eta', v_pin_row.eta);
end $$;
grant execute on function public.place_order(jsonb, jsonb) to anon, authenticated;

create or replace function public.subscribe_newsletter(p_name text, p_email text)
returns text language plpgsql security definer set search_path = public as $$
begin
  p_email := lower(trim(p_email));
  if p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Please enter a valid email'; end if;
  if exists (select 1 from public.newsletter_subscribers where lower(email) = p_email) then return 'exists'; end if;
  insert into public.newsletter_subscribers(name, email) values (left(trim(p_name),120), p_email);
  return 'ok';
end $$;
grant execute on function public.subscribe_newsletter(text, text) to anon, authenticated;

-- admin: change order status (restores stock on cancel)
create or replace function public.admin_set_order_status(p_order uuid, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_old text; v_no text; r record; c jsonb;
begin
  if not public.is_admin() then raise exception 'Not authorised'; end if;
  select status, order_no into v_old, v_no from public.orders where id = p_order for update;
  if not found then raise exception 'Order not found'; end if;
  if p_status = v_old then return; end if;
  if p_status = 'Cancelled' and v_old <> 'Cancelled' then
    for r in select * from public.order_items where order_id = p_order loop
      if r.kind = 'product' and r.product_id is not null then
        update public.products set stock = stock + r.qty where id = r.product_id;
        insert into public.inventory_movements(product_id, change, reason, ref, created_by) values (r.product_id, r.qty, 'cancel', v_no, auth.uid());
      elsif r.kind = 'hamper' then
        for c in select * from jsonb_array_elements(r.components) loop
          update public.products set stock = stock + (c->>'qty')::int * r.qty where id = (c->>'product_id')::uuid;
          insert into public.inventory_movements(product_id, change, reason, ref, created_by)
            values ((c->>'product_id')::uuid, (c->>'qty')::int * r.qty, 'cancel', v_no, auth.uid());
        end loop;
      end if;
    end loop;
  end if;
  update public.orders set status = p_status where id = p_order;
  insert into public.order_activity(order_id, action, note, actor) values (p_order, v_old || ' → ' || p_status, p_note, auth.uid());
end $$;
grant execute on function public.admin_set_order_status(uuid, text, text) to authenticated;

create or replace function public.admin_adjust_stock(p_product uuid, p_change int, p_reason text, p_ref text default null)
returns int language plpgsql security definer set search_path = public as $$
declare v_new int;
begin
  if not public.is_admin() then raise exception 'Not authorised'; end if;
  update public.products set stock = stock + p_change where id = p_product returning stock into v_new;
  if v_new is null then raise exception 'Product not found'; end if;
  if v_new < 0 then raise exception 'Stock cannot go below zero'; end if;
  insert into public.inventory_movements(product_id, change, reason, ref, created_by) values (p_product, p_change, p_reason, p_ref, auth.uid());
  return v_new;
end $$;
grant execute on function public.admin_adjust_stock(uuid, int, text, text) to authenticated;

-- =====================================================================
--  STORAGE: product images (public read, admin write)
-- =====================================================================
insert into storage.buckets (id, name, public) values ('product-images','product-images', true)
  on conflict (id) do nothing;
drop policy if exists "rm images admin insert" on storage.objects;
create policy "rm images admin insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'product-images' and public.is_admin());
drop policy if exists "rm images admin update" on storage.objects;
create policy "rm images admin update" on storage.objects for update to authenticated
  using (bucket_id = 'product-images' and public.is_admin());
drop policy if exists "rm images admin delete" on storage.objects;
create policy "rm images admin delete" on storage.objects for delete to authenticated
  using (bucket_id = 'product-images' and public.is_admin());

-- =====================================================================
--  SEED (clearly-labelled SAMPLE data only — replace from admin panel)
-- =====================================================================
insert into public.categories(slug, name, description, sort) values
  ('chocolates','Craft Chocolates','Bars, thins, pralines and bonbons.',1),
  ('coffee','Coffee Beans','Whole bean, filter and espresso grinds.',2),
  ('hampers','Gift Hampers','Fixed hampers or build your own.',3),
  ('festive','Festive Specials','Diwali, Pongal, Christmas and more.',4),
  ('corporate','Corporate Gifting','Bulk orders and custom branding.',5)
on conflict (slug) do nothing;

insert into public.hamper_boxes(name, capacity, price, sort)
select * from (values ('Small',4,150::numeric,1),('Medium',6,250::numeric,2),('Large',9,350::numeric,3),('Premium',12,550::numeric,4)) v
where not exists (select 1 from public.hamper_boxes);

insert into public.products(sku,name,category_slug,subcategory,short_desc,size_label,cocoa_pct,roast_level,mrp,price,gst_rate,hsn,stock,is_bestseller,is_gift,is_new,is_sample,sort) values
 ('SAMPLE-CH-001','70% Dark Chocolate Bar','chocolates','Chocolate Bars','Deep, fruity, a clean snap.','60 g',70,null,395,350,18,'1806',40,true,false,false,true,1),
 ('SAMPLE-CH-002','Filter Coffee Milk Chocolate','chocolates','Chocolate Bars','Milk chocolate with a filter coffee kick.','60 g',40,null,395,395,18,'1806',40,true,false,true,true,2),
 ('SAMPLE-CH-003','Assorted Bonbons · Box of 9','chocolates','Bonbons','Nine hand-finished pieces, rotating flavours.','9 pcs · 110 g',null,null,950,950,18,'1806',20,true,true,false,true,3),
 ('SAMPLE-CH-004','Hazelnut Pralines · Box of 12','chocolates','Pralines','Roasted hazelnut, milk chocolate, crunch.','12 pcs · 140 g',null,null,1100,1100,18,'1806',15,false,true,true,true,4),
 ('SAMPLE-CH-005','Sea Salt Dark Thins','chocolates','Chocolate Thins','Ultra-thin 65% discs with a pinch of salt.','80 g',65,null,450,450,18,'1806',0,false,false,true,true,5),
 ('SAMPLE-CF-001','Romancham House Blend','coffee','Coffee Beans','The café pour, medium roast.','250 g',null,'Medium',650,599,5,'0901',30,true,false,false,true,6),
 ('SAMPLE-CF-002','South Indian Filter Coffee','coffee','Filter Coffee','Coffee–chicory blend for the davara-tumbler.','250 g',null,'Medium-Dark',450,450,5,'0901',30,false,false,true,true,7),
 ('SAMPLE-CF-003','Single Estate Espresso','coffee','Espresso Coffee','Dark roast, chocolatey, built for espresso.','250 g',null,'Dark',725,725,5,'0901',25,false,false,true,true,8),
 ('SAMPLE-HM-001','The Little Indulgence Box','hampers','Chocolate Hampers','Two bars, four bonbons and a handwritten note.','Small hamper',null,null,1499,1499,18,null,10,false,true,false,true,9),
 ('SAMPLE-HM-002','Coffee & Chocolate Duo','hampers','Coffee Hampers','House blend coffee with a 70% dark bar.','Medium hamper',null,null,1250,1199,18,null,10,true,true,false,true,10),
 ('SAMPLE-HM-003','Celebration Hamper','hampers','Celebration Hampers','Bars, bonbons and coffee for the big days.','Large hamper',null,null,2499,2499,18,null,8,false,true,false,true,11),
 ('SAMPLE-FS-001','Diwali Sweet Box','festive','Diwali','Festive chocolates in a keepsake box.','16 pcs',null,null,1299,1299,18,null,12,false,true,true,true,12)
on conflict (sku) do nothing;
update public.products set hamper_eligible = false where category_slug in ('hampers','festive') and is_sample;

-- Chennai pincodes (600001–600130) — disable/edit any from admin
insert into public.delivery_pincodes(pincode, area, charge, eta)
select lpad(g::text,6,'0'), 'Chennai', 80, '1–2 days' from generate_series(600001, 600130) g
on conflict (pincode) do nothing;
update public.delivery_pincodes set area = 'Anna Nagar', charge = 50, eta = 'Same / next day'
 where pincode in ('600040','600101','600102') and area = 'Chennai';

insert into public.business_settings(key, value) values
  ('whatsapp_number',''), ('email',''), ('address','Anna Nagar, Chennai'),
  ('hours','12:00 PM – 12:00 AM, every day'), ('gstin',''), ('fssai',''),
  ('instagram','https://instagram.com/'), ('free_shipping_threshold','999'),
  ('maps_query','Romancham Anna Nagar Chennai'),
  ('announcement','Free Chennai delivery on orders above ₹999 · Build your own hamper · Café open 12 PM – 12 AM'),
  ('heat_notice','Chocolates are heat-sensitive. Please keep them in a cool place on arrival.')
on conflict (key) do nothing;
