-- ---------------------------------------------------------------------------
-- Core content model: every experience is either a Spot or an Itinerary.
--
--   Spot      — one real-world place, synced from the place provider. Users
--               never author spots; they rate, save, complete and comment on
--               them. Identified by a stable `spot_key` so duplicates cannot
--               exist.
--   Itinerary — a user- (or Trav-) curated journey over 2+ distinct spots.
--               Identified by `route_signature` so near-identical itineraries
--               cannot be published twice.
--
-- This migration only introduces the taxonomy + identity keys. Ratings live in
-- 20260730120100, and the write paths (sync_spot / publish_itinerary) live in
-- 20260730120200.
-- ---------------------------------------------------------------------------

create extension if not exists pgcrypto with schema extensions;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'experience_kind') then
    create type public.experience_kind as enum ('spot', 'itinerary');
  end if;
end;
$$;

alter table public.experiences
  add column if not exists kind public.experience_kind not null default 'itinerary';
alter table public.experiences
  add column if not exists spot_key text;
alter table public.experiences
  add column if not exists route_signature text;
alter table public.experiences
  add column if not exists latitude double precision;
alter table public.experiences
  add column if not exists longitude double precision;
alter table public.experiences
  add column if not exists category text;
-- Editorial promotion, used as a recommendation signal.
alter table public.experiences
  add column if not exists is_featured boolean not null default false;

-- ---------------------------------------------------------------------------
-- Identity helpers
-- ---------------------------------------------------------------------------

-- Canonical identity for a physical place. Provider IDs win; otherwise we fall
-- back to a normalized name plus coordinates rounded to ~11m so the same café
-- discovered from two slightly different searches collapses to one spot.
create or replace function public.spot_identity_key(
  p_place_id text,
  p_name text,
  p_latitude double precision,
  p_longitude double precision
)
returns text
language sql
immutable
as $$
  select case
    when coalesce(btrim(p_place_id), '') <> ''
      then 'place:' || lower(btrim(p_place_id))
    when coalesce(btrim(p_name), '') <> ''
      then 'geo:'
        || regexp_replace(lower(btrim(p_name)), '[^a-z0-9]', '', 'g')
        || ':' || to_char(round(coalesce(p_latitude, 0)::numeric, 4), 'FM990.0000')
        || ':' || to_char(round(coalesce(p_longitude, 0)::numeric, 4), 'FM990.0000')
    else null
  end;
$$;

-- Order-sensitive fingerprint of an itinerary's stops.
create or replace function public.itinerary_route_signature(p_stop_keys text[])
returns text
language sql
immutable
as $$
  select case
    when p_stop_keys is null or array_length(p_stop_keys, 1) is null then null
    else encode(
      extensions.digest(convert_to(array_to_string(p_stop_keys, '>'), 'UTF8'), 'sha256'),
      'hex'
    )
  end;
$$;

-- Signature derived from the persisted stops of an existing itinerary.
create or replace function public.itinerary_signature_for(p_experience_id uuid)
returns text
language sql
stable
as $$
  select public.itinerary_route_signature(
    array_agg(
      public.spot_identity_key(s.place_id, s.name, s.latitude, s.longitude)
      order by s.order_index
    )
  )
  from public.stops s
  where s.experience_id = p_experience_id;
$$;

-- ---------------------------------------------------------------------------
-- Stops: dedupe key + link to the canonical spot experience
-- ---------------------------------------------------------------------------

alter table public.stops
  add column if not exists stop_key text;
alter table public.stops
  add column if not exists spot_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'stops_spot_fk'
  ) then
    alter table public.stops
      add constraint stops_spot_fk
      foreign key (spot_id) references public.experiences (id) on delete set null;
  end if;
end;
$$;

create or replace function public.tg_stops_identity()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.stop_key := public.spot_identity_key(new.place_id, new.name, new.latitude, new.longitude);
  return new;
end;
$$;

drop trigger if exists stops_identity_biu on public.stops;
create trigger stops_identity_biu
  before insert or update of place_id, name, latitude, longitude on public.stops
  for each row execute function public.tg_stops_identity();

update public.stops
  set stop_key = public.spot_identity_key(place_id, name, latitude, longitude)
  where stop_key is null;

-- An itinerary may not visit the same spot twice.
do $$
begin
  -- Collapse pre-existing duplicates before enforcing the constraint.
  delete from public.stops s
  using (
    select id,
           row_number() over (
             partition by experience_id, stop_key order by order_index, created_at
           ) as rn
    from public.stops
    where stop_key is not null
  ) d
  where s.id = d.id and d.rn > 1;
end;
$$;

create unique index if not exists uq_stops_experience_stop_key
  on public.stops (experience_id, stop_key)
  where stop_key is not null;

create index if not exists idx_stops_spot on public.stops (spot_id);
create index if not exists idx_stops_stop_key on public.stops (stop_key);

-- ---------------------------------------------------------------------------
-- Representative coordinate for each experience (distance ranking in the feed)
-- ---------------------------------------------------------------------------

create or replace function public.recompute_experience_geometry(p_experience_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.experiences e
    set latitude = g.latitude,
        longitude = g.longitude
  from (
    select avg(s.latitude) as latitude, avg(s.longitude) as longitude
    from public.stops s
    where s.experience_id = p_experience_id
      and s.latitude is not null and s.longitude is not null
      and not (s.latitude = 0 and s.longitude = 0)
  ) g
  where e.id = p_experience_id
    and g.latitude is not null;
end;
$$;

create or replace function public.tg_stops_geometry()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.recompute_experience_geometry(coalesce(new.experience_id, old.experience_id));
  return null;
end;
$$;

drop trigger if exists stops_geometry_aiud on public.stops;
create trigger stops_geometry_aiud
  after insert or update or delete on public.stops
  for each row execute function public.tg_stops_geometry();

-- ---------------------------------------------------------------------------
-- Backfill the taxonomy from existing rows
-- ---------------------------------------------------------------------------

-- Anything that resolves to a single place is a spot; everything else is an
-- itinerary. `source_place_id` marks rows already synced from the provider.
update public.experiences e
  set kind = case
    when e.source_place_id is not null then 'spot'::public.experience_kind
    when coalesce((select count(*) from public.stops s where s.experience_id = e.id), 0) > 1
      then 'itinerary'::public.experience_kind
    when coalesce(array_length(e.stops, 1), 0) > 1 then 'itinerary'::public.experience_kind
    else 'spot'::public.experience_kind
  end;

update public.experiences e
  set spot_key = coalesce(
    public.spot_identity_key(e.source_place_id, null, null, null),
    (
      select s.stop_key from public.stops s
      where s.experience_id = e.id and s.stop_key is not null
      order by s.order_index limit 1
    ),
    public.spot_identity_key(null, e.title, e.latitude, e.longitude)
  )
  where e.kind = 'spot' and e.spot_key is null;

-- Keep only the oldest row per spot identity so the unique index can be built.
-- Losing duplicates are demoted rather than deleted: engagement rows still
-- point at them, and unpublishing keeps them out of every feed.
with ranked as (
  select id,
         row_number() over (partition by spot_key order by created_at, id) as rn
  from public.experiences
  where kind = 'spot' and spot_key is not null
)
update public.experiences e
  set spot_key = null,
      is_published = false
from ranked r
where e.id = r.id and r.rn > 1;

update public.experiences e
  set route_signature = public.itinerary_signature_for(e.id)
  where e.kind = 'itinerary' and e.route_signature is null;

with ranked as (
  select id,
         row_number() over (partition by route_signature order by created_at, id) as rn
  from public.experiences
  where kind = 'itinerary' and route_signature is not null
)
update public.experiences e
  set route_signature = null
from ranked r
where e.id = r.id and r.rn > 1;

update public.experiences e
  set latitude = g.latitude,
      longitude = g.longitude
from (
  select experience_id,
         avg(latitude) as latitude,
         avg(longitude) as longitude
  from public.stops
  where latitude is not null and longitude is not null
    and not (latitude = 0 and longitude = 0)
  group by experience_id
) g
where e.id = g.experience_id and e.latitude is null;

update public.experiences e
  set category = p.basic_category
from public.places p
where e.source_place_id = p.id and e.category is null;

-- ---------------------------------------------------------------------------
-- Uniqueness + lookup indexes
-- ---------------------------------------------------------------------------

create unique index if not exists uq_experiences_spot_key
  on public.experiences (spot_key)
  where kind = 'spot' and spot_key is not null;

create unique index if not exists uq_experiences_route_signature
  on public.experiences (route_signature)
  where kind = 'itinerary' and route_signature is not null;

create index if not exists idx_experiences_kind_created
  on public.experiences (kind, created_at desc)
  where is_published = true;

create index if not exists idx_experiences_coordinates
  on public.experiences (latitude, longitude)
  where is_published = true;

create index if not exists idx_experiences_featured
  on public.experiences (is_featured)
  where is_featured = true;

-- ---------------------------------------------------------------------------
-- Itineraries need at least two distinct stops to stay published
-- ---------------------------------------------------------------------------

create or replace function public.experience_stop_count(p_experience_id uuid)
returns integer
language sql
stable
as $$
  select count(distinct coalesce(stop_key, id::text))::integer
  from public.stops
  where experience_id = p_experience_id;
$$;

-- Enforced on the stops side because an itinerary row is always written before
-- its stops: unpublishing a one-stop itinerary is the safety net for any write
-- path that bypasses publish_itinerary().
create or replace function public.tg_itinerary_min_stops()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_experience_id uuid := coalesce(new.experience_id, old.experience_id);
  v_kind public.experience_kind;
  v_count integer;
begin
  select kind into v_kind from public.experiences where id = v_experience_id;
  if v_kind is distinct from 'itinerary'::public.experience_kind then
    return null;
  end if;

  v_count := public.experience_stop_count(v_experience_id);

  update public.experiences
    set is_published = (v_count >= 2),
        route_signature = case
          when v_count >= 2 then coalesce(route_signature, public.itinerary_signature_for(v_experience_id))
          else route_signature
        end
    where id = v_experience_id
      and is_published <> (v_count >= 2);

  return null;
end;
$$;

drop trigger if exists itinerary_min_stops_aiud on public.stops;
create trigger itinerary_min_stops_aiud
  after insert or delete on public.stops
  for each row execute function public.tg_itinerary_min_stops();

update public.experiences e
  set is_published = false
  where e.kind = 'itinerary'
    and e.is_published = true
    and public.experience_stop_count(e.id) < 2
    -- Legacy rows whose stops only exist in the denormalized array are left
    -- alone; the normalized table is authoritative only once populated.
    and exists (select 1 from public.stops s where s.experience_id = e.id);

-- ---------------------------------------------------------------------------
-- Users author itineraries only. Spots arrive through sync_spot().
-- ---------------------------------------------------------------------------

drop policy if exists "Users can insert their own experiences" on public.experiences;
drop policy if exists "Users can create their itineraries" on public.experiences;
create policy "Users can create their itineraries"
  on public.experiences for insert
  with check (auth.uid() = user_id and kind = 'itinerary');
