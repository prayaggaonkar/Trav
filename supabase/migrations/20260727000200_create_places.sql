-- Places catalog populated by backend_data_pipeline (Overture Maps POIs and
-- generated itineraries). Previously created ad-hoc via the dashboard SQL
-- editor; this versions the DDL and applies least-privilege policies:
-- public read, writes only via the service role (which bypasses RLS).

create table if not exists public.places (
  id text primary key,                 -- Overture place ID or generated itinerary id
  name text not null,
  basic_category text not null,
  latitude double precision not null,
  longitude double precision not null,
  city text not null default 'Berkeley',
  image_urls text[] not null default '{}',
  stops text[] not null default '{}',  -- JSON-encoded stop payloads for itineraries
  created_at timestamptz not null default now()
);

alter table public.places
  add column if not exists city text not null default 'Berkeley';
alter table public.places
  add column if not exists image_urls text[] not null default '{}';

create index if not exists idx_places_coordinates on public.places (latitude, longitude);
create index if not exists idx_places_category on public.places (basic_category);
create index if not exists idx_places_city on public.places (city);

alter table public.places enable row level security;

drop policy if exists "Allow public read access" on public.places;
drop policy if exists "Places are publicly readable" on public.places;
create policy "Places are publicly readable"
  on public.places for select using (true);

-- Remove the effectively-open FOR ALL policy from the ad-hoc setup.
drop policy if exists "Allow service role write access" on public.places;

grant select on public.places to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Stable UUID bridge
-- The iOS client models every feed item as a UUID. Overture place ids are
-- 32-char strings, so the client derives a deterministic UUID via SHA-256
-- (see StableUUID.from in Swift). This function mirrors that derivation so
-- place rows can be looked up by their client-side UUID.
-- ---------------------------------------------------------------------------
create extension if not exists pgcrypto with schema extensions;

create or replace function public.stable_uuid(raw text)
returns uuid
language sql
immutable
as $$
  select case
    when raw ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then raw::uuid
    else (
      -- SHA-256, first 16 bytes, with UUID version nibble forced to 5 and
      -- the variant bits forced to 10xx — identical to StableUUID.from.
      select (
        substr(h, 1, 12)
        || '5' || substr(h, 14, 1)
        || substr(h, 15, 2)
        || to_hex((('x' || substr(h, 17, 1))::bit(4)::int & 3) | 8)
        || substr(h, 18, 1)
        || substr(h, 19, 14)
      )::uuid
      from (select encode(extensions.digest(convert_to(raw, 'UTF8'), 'sha256'), 'hex') as h) s
    )
  end
$$;

alter table public.places
  add column if not exists client_uuid uuid generated always as (public.stable_uuid(id)) stored;

create unique index if not exists idx_places_client_uuid on public.places (client_uuid);

-- Link place-derived experience rows back to their source place.
alter table public.experiences
  add column if not exists source_place_id text references public.places (id) on delete set null;
