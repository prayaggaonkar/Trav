-- Cities catalog: moves the globe's city list out of the app binary and into
-- the database so new destinations ship without an App Store release.
-- Seed ids match the previous in-app catalog (MockData.cities) so existing
-- rows/links that referenced those ids keep working.

create table if not exists public.cities (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  country_code char(2) not null,
  latitude double precision not null,
  longitude double precision not null,
  hero_image_url text,
  timezone text not null,
  experience_count integer not null default 0,
  creator_count integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists idx_cities_active on public.cities (is_active, name);

alter table public.cities enable row level security;

drop policy if exists "Cities are publicly readable" on public.cities;
create policy "Cities are publicly readable"
  on public.cities for select using (true);

drop policy if exists "Authenticated users can insert cities" on public.cities;
create policy "Authenticated users can insert cities"
  on public.cities for insert with check (auth.role() = 'authenticated');

drop policy if exists "Authenticated users can update cities" on public.cities;
create policy "Authenticated users can update cities"
  on public.cities for update using (auth.role() = 'authenticated');

grant select on public.cities to anon;
grant select, insert, update on public.cities to authenticated;

insert into public.cities (id, name, slug, country_code, latitude, longitude, hero_image_url, timezone) values
  ('c1000001-0000-0000-0000-000000000001', 'San Francisco', 'san-francisco', 'US', 37.7749, -122.4194, 'https://images.unsplash.com/photo-1501594907352-04cda38ebc29?w=1200&q=80', 'America/Los_Angeles'),
  ('c1000002-0000-0000-0000-000000000002', 'Tokyo', 'tokyo', 'JP', 35.6762, 139.6503, 'https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=1200&q=80', 'Asia/Tokyo'),
  ('c1000003-0000-0000-0000-000000000003', 'Paris', 'paris', 'FR', 48.8566, 2.3522, 'https://images.unsplash.com/photo-1502602898657-3e91760cbb34?w=1200&q=80', 'Europe/Paris'),
  ('c1000004-0000-0000-0000-000000000004', 'New York', 'new-york', 'US', 40.7128, -74.0060, 'https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?w=1200&q=80', 'America/New_York'),
  ('c1000005-0000-0000-0000-000000000005', 'London', 'london', 'GB', 51.5074, -0.1278, 'https://images.unsplash.com/photo-1513635269975-59663e0ac1ad?w=1200&q=80', 'Europe/London'),
  ('c1000006-0000-0000-0000-000000000006', 'Barcelona', 'barcelona', 'ES', 41.3874, 2.1686, 'https://images.unsplash.com/photo-1583422409516-2895a77efded?w=1200&q=80', 'Europe/Madrid'),
  ('c1000007-0000-0000-0000-000000000007', 'Sydney', 'sydney', 'AU', -33.8688, 151.2093, 'https://images.unsplash.com/photo-1506973035872-a4ec16b8e8d9?w=1200&q=80', 'Australia/Sydney'),
  ('c1000008-0000-0000-0000-000000000008', 'Seoul', 'seoul', 'KR', 37.5665, 126.9780, 'https://images.unsplash.com/photo-1517154421773-0529f29ea451?w=1200&q=80', 'Asia/Seoul'),
  ('c1000009-0000-0000-0000-000000000009', 'Berkeley', 'berkeley', 'US', 37.8715, -122.2730, 'https://images.unsplash.com/photo-1584017911766-d451b3d0e843?w=1200&q=80', 'America/Los_Angeles')
on conflict (slug) do nothing;

-- ---------------------------------------------------------------------------
-- experiences.city_id: real FK alongside the legacy `city` display text
-- ---------------------------------------------------------------------------
alter table public.experiences
  add column if not exists city_id uuid references public.cities (id);

update public.experiences e
set city_id = c.id
from public.cities c
where e.city_id is null
  and lower(trim(e.city)) = lower(c.name);

create index if not exists idx_experiences_city_id_created
  on public.experiences (city_id, created_at desc);

-- profiles.home_city_id FK was deferred until cities existed; add it now.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_home_city_fk'
  ) then
    alter table public.profiles
      add constraint profiles_home_city_fk
      foreign key (home_city_id) references public.cities (id)
      on delete set null
      not valid;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Keep denormalized per-city counters fresh
-- ---------------------------------------------------------------------------
create or replace function public.tg_cities_experience_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' and new.city_id is not null then
    update public.cities set experience_count = experience_count + 1
      where id = new.city_id;
    return new;
  elsif tg_op = 'DELETE' and old.city_id is not null then
    update public.cities set experience_count = greatest(experience_count - 1, 0)
      where id = old.city_id;
    return old;
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists cities_experience_counts_ai on public.experiences;
create trigger cities_experience_counts_ai
  after insert on public.experiences
  for each row execute function public.tg_cities_experience_counts();

drop trigger if exists cities_experience_counts_ad on public.experiences;
create trigger cities_experience_counts_ad
  after delete on public.experiences
  for each row execute function public.tg_cities_experience_counts();

update public.cities c
set experience_count = (select count(*) from public.experiences e where e.city_id = c.id),
    creator_count = (select count(distinct e.user_id) from public.experiences e where e.city_id = c.id);
