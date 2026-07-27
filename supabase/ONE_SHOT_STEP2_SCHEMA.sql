-- RUN THIS SECOND, after ONE_SHOT_STEP1_ENUM.sql succeeded.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- profiles (assume table exists from auth bootstrap; add missing columns)
-- ---------------------------------------------------------------------------
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists display_name text;
alter table public.profiles add column if not exists bio text;
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists home_city_id uuid;
alter table public.profiles add column if not exists home_city_name text;
alter table public.profiles add column if not exists follower_count integer not null default 0;
alter table public.profiles add column if not exists following_count integer not null default 0;
alter table public.profiles add column if not exists experience_count integer not null default 0;
alter table public.profiles add column if not exists completion_count integer not null default 0;
alter table public.profiles add column if not exists is_verified boolean not null default false;
alter table public.profiles add column if not exists selected_vibes text[] not null default '{}';
alter table public.profiles add column if not exists onboarding_location text;
alter table public.profiles add column if not exists created_at timestamptz not null default now();
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

-- ---------------------------------------------------------------------------
-- experiences: create if missing, then add EVERY column the app needs
-- ---------------------------------------------------------------------------
create table if not exists public.experiences (
  id uuid primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null default '',
  created_at timestamptz not null default now()
);

alter table public.experiences add column if not exists user_id uuid references public.profiles (id) on delete cascade;
alter table public.experiences add column if not exists title text not null default '';
alter table public.experiences add column if not exists description text not null default '';
alter table public.experiences add column if not exists city text not null default '';
alter table public.experiences add column if not exists city_id uuid;
alter table public.experiences add column if not exists stops text[] not null default '{}';
alter table public.experiences add column if not exists image jsonb;
alter table public.experiences add column if not exists rating jsonb;
alter table public.experiences add column if not exists save_count integer not null default 0;
alter table public.experiences add column if not exists like_count integer not null default 0;
alter table public.experiences add column if not exists completion_count integer not null default 0;
alter table public.experiences add column if not exists comment_count integer not null default 0;
alter table public.experiences add column if not exists is_published boolean not null default true;
alter table public.experiences add column if not exists source_place_id text;
alter table public.experiences add column if not exists created_at timestamptz not null default now();

-- Normalize legacy image shapes (text / text[]) → jsonb when needed
do $$
declare
  col_type text;
begin
  select data_type into col_type
  from information_schema.columns
  where table_schema = 'public' and table_name = 'experiences' and column_name = 'image';

  if col_type = 'text' then
    alter table public.experiences
      alter column image type jsonb
      using case when image is null then null else to_jsonb(array[image]) end;
  elsif col_type = 'ARRAY' then
    alter table public.experiences
      alter column image type jsonb
      using case when image is null then null else to_jsonb(image) end;
  end if;
end
$$;

update public.experiences
set is_published = false, description = coalesce(description, '')
where description = '__trav_bookmark__';

create index if not exists idx_experiences_city_created on public.experiences (city, created_at desc);
create index if not exists idx_experiences_user on public.experiences (user_id);
create index if not exists idx_experiences_published_created
  on public.experiences (created_at desc) where is_published = true;

alter table public.experiences enable row level security;

drop policy if exists "Experiences are publicly readable" on public.experiences;
create policy "Experiences are publicly readable"
  on public.experiences for select using (true);

drop policy if exists "Users can insert their own experiences" on public.experiences;
create policy "Users can insert their own experiences"
  on public.experiences for insert with check (auth.uid() = user_id);

drop policy if exists "Users can update their own experiences" on public.experiences;
create policy "Users can update their own experiences"
  on public.experiences for update using (auth.uid() = user_id);

drop policy if exists "Users can delete their own experiences" on public.experiences;
create policy "Users can delete their own experiences"
  on public.experiences for delete using (auth.uid() = user_id);

grant select on public.experiences to anon;
grant select, insert, update, delete on public.experiences to authenticated;

-- ---------------------------------------------------------------------------
-- cities
-- ---------------------------------------------------------------------------
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

grant select on public.cities to anon, authenticated;

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

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'experiences_city_id_fkey') then
    begin
      alter table public.experiences
        add constraint experiences_city_id_fkey
        foreign key (city_id) references public.cities (id)
        on delete set null;
    exception when others then
      null;
    end;
  end if;
end
$$;

update public.experiences e
set city_id = c.id
from public.cities c
where e.city_id is null
  and nullif(trim(e.city), '') is not null
  and lower(trim(e.city)) = lower(c.name);

create index if not exists idx_experiences_city_id_created
  on public.experiences (city_id, created_at desc);

-- ---------------------------------------------------------------------------
-- follows (canonical) ← merge from ad-hoc followers if present
-- ---------------------------------------------------------------------------
create table if not exists public.follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  following_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint follows_no_self check (follower_id <> following_id)
);

create index if not exists idx_follows_following on public.follows (following_id, created_at desc);
create index if not exists idx_follows_follower on public.follows (follower_id, created_at desc);

alter table public.follows enable row level security;

drop policy if exists "Follows are publicly readable" on public.follows;
create policy "Follows are publicly readable"
  on public.follows for select using (true);

drop policy if exists "Users can follow others" on public.follows;
create policy "Users can follow others"
  on public.follows for insert with check (auth.uid() = follower_id);

drop policy if exists "Users can unfollow" on public.follows;
create policy "Users can unfollow"
  on public.follows for delete using (auth.uid() = follower_id);

grant select on public.follows to anon;
grant select, insert, delete on public.follows to authenticated;

do $$
begin
  if to_regclass('public.followers') is not null then
    insert into public.follows (follower_id, following_id, created_at)
    select f.follower_id, f.following_id, coalesce(f.created_at, now())
    from public.followers f
    where f.follower_id <> f.following_id
      and exists (select 1 from public.profiles p where p.id = f.follower_id)
      and exists (select 1 from public.profiles p where p.id = f.following_id)
    on conflict (follower_id, following_id) do nothing;
    drop table public.followers cascade;
  end if;
end
$$;

create or replace function public.tg_follows_counts()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update public.profiles set following_count = following_count + 1, updated_at = now() where id = new.follower_id;
    update public.profiles set follower_count = follower_count + 1, updated_at = now() where id = new.following_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.profiles set following_count = greatest(following_count - 1, 0), updated_at = now() where id = old.follower_id;
    update public.profiles set follower_count = greatest(follower_count - 1, 0), updated_at = now() where id = old.following_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists follows_counts_ai on public.follows;
create trigger follows_counts_ai after insert on public.follows
  for each row execute function public.tg_follows_counts();
drop trigger if exists follows_counts_ad on public.follows;
create trigger follows_counts_ad after delete on public.follows
  for each row execute function public.tg_follows_counts();

-- ---------------------------------------------------------------------------
-- experience_saves ← merge from saved_experiences if present
-- ---------------------------------------------------------------------------
create table if not exists public.experience_saves (
  user_id uuid not null references public.profiles (id) on delete cascade,
  experience_id uuid not null references public.experiences (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, experience_id)
);

create index if not exists idx_experience_saves_user on public.experience_saves (user_id, created_at desc);
create index if not exists idx_experience_saves_experience on public.experience_saves (experience_id);

alter table public.experience_saves enable row level security;

drop policy if exists "Saves are publicly readable" on public.experience_saves;
create policy "Saves are publicly readable"
  on public.experience_saves for select using (true);

drop policy if exists "Users can save experiences" on public.experience_saves;
create policy "Users can save experiences"
  on public.experience_saves for insert with check (auth.uid() = user_id);

drop policy if exists "Users can unsave experiences" on public.experience_saves;
drop policy if exists "Users can unsaved experiences" on public.experience_saves;
create policy "Users can unsave experiences"
  on public.experience_saves for delete using (auth.uid() = user_id);

grant select on public.experience_saves to anon;
grant select, insert, delete on public.experience_saves to authenticated;

do $$
begin
  if to_regclass('public.saved_experiences') is not null then
    insert into public.experience_saves (user_id, experience_id, created_at)
    select s.user_id, s.experience_id, coalesce(s.created_at, now())
    from public.saved_experiences s
    where exists (select 1 from public.profiles p where p.id = s.user_id)
      and exists (select 1 from public.experiences e where e.id = s.experience_id)
    on conflict (user_id, experience_id) do nothing;
    drop table public.saved_experiences cascade;
  end if;
end
$$;

create or replace function public.tg_experience_saves_counts()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update public.experiences set save_count = save_count + 1 where id = new.experience_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.experiences set save_count = greatest(save_count - 1, 0) where id = old.experience_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists experience_saves_counts_ai on public.experience_saves;
create trigger experience_saves_counts_ai after insert on public.experience_saves
  for each row execute function public.tg_experience_saves_counts();
drop trigger if exists experience_saves_counts_ad on public.experience_saves;
create trigger experience_saves_counts_ad after delete on public.experience_saves
  for each row execute function public.tg_experience_saves_counts();

update public.experiences e
set save_count = (select count(*) from public.experience_saves s where s.experience_id = e.id);

-- ---------------------------------------------------------------------------
-- experience_completions
-- ---------------------------------------------------------------------------
create table if not exists public.experience_completions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  experience_id uuid not null references public.experiences (id) on delete cascade,
  completed_at timestamptz not null default now(),
  note text,
  photo_urls text[] not null default '{}',
  unique (user_id, experience_id)
);

create index if not exists idx_experience_completions_user
  on public.experience_completions (user_id, completed_at desc);
create index if not exists idx_experience_completions_experience
  on public.experience_completions (experience_id);

alter table public.experience_completions enable row level security;

drop policy if exists "Completions are publicly readable" on public.experience_completions;
create policy "Completions are publicly readable"
  on public.experience_completions for select using (true);

drop policy if exists "Users can complete experiences" on public.experience_completions;
create policy "Users can complete experiences"
  on public.experience_completions for insert with check (auth.uid() = user_id);

drop policy if exists "Users can update their completions" on public.experience_completions;
create policy "Users can update their completions"
  on public.experience_completions for update using (auth.uid() = user_id);

drop policy if exists "Users can delete their completions" on public.experience_completions;
create policy "Users can delete their completions"
  on public.experience_completions for delete using (auth.uid() = user_id);

grant select on public.experience_completions to anon;
grant select, insert, update, delete on public.experience_completions to authenticated;

update public.experiences e
set completion_count = (
  select count(*) from public.experience_completions c where c.experience_id = e.id
);

-- ---------------------------------------------------------------------------
-- notifications
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  actor_id uuid not null references public.profiles (id) on delete cascade,
  type public.notification_type not null,
  reference_id uuid,
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  constraint notifications_no_self check (user_id <> actor_id)
);

create index if not exists idx_notifications_user_created
  on public.notifications (user_id, created_at desc);
create index if not exists idx_notifications_user_unread
  on public.notifications (user_id) where is_read = false;

alter table public.notifications enable row level security;

drop policy if exists "Users can read their notifications" on public.notifications;
create policy "Users can read their notifications"
  on public.notifications for select using (auth.uid() = user_id);

drop policy if exists "Users can update their notifications" on public.notifications;
create policy "Users can update their notifications"
  on public.notifications for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

grant select, update on public.notifications to authenticated;

create or replace function public.insert_notification(
  p_user_id uuid,
  p_actor_id uuid,
  p_type public.notification_type,
  p_reference_id uuid
) returns void language plpgsql security definer set search_path = public as $$
begin
  if p_user_id is null or p_actor_id is null or p_user_id = p_actor_id then
    return;
  end if;
  insert into public.notifications (user_id, actor_id, type, reference_id)
  values (p_user_id, p_actor_id, p_type, p_reference_id);
end;
$$;

revoke all on function public.insert_notification(uuid, uuid, public.notification_type, uuid) from public;

create or replace function public.tg_notify_on_follow()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.insert_notification(new.following_id, new.follower_id, 'follow', new.follower_id);
  return new;
end;
$$;

create or replace function public.tg_notify_on_experience_save()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  owner_id uuid;
begin
  select user_id into owner_id from public.experiences where id = new.experience_id;
  perform public.insert_notification(owner_id, new.user_id, 'save', new.experience_id);
  return new;
end;
$$;

create or replace function public.tg_notify_on_new_experience()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.is_published is distinct from true then
    return new;
  end if;
  insert into public.notifications (user_id, actor_id, type, reference_id)
  select f.follower_id, new.user_id, 'new_experience'::public.notification_type, new.id
  from public.follows f
  where f.following_id = new.user_id and f.follower_id <> new.user_id;
  return new;
end;
$$;

drop trigger if exists notify_on_follow_ai on public.follows;
create trigger notify_on_follow_ai after insert on public.follows
  for each row execute function public.tg_notify_on_follow();

drop trigger if exists notify_on_experience_save_ai on public.experience_saves;
create trigger notify_on_experience_save_ai after insert on public.experience_saves
  for each row execute function public.tg_notify_on_experience_save();

drop trigger if exists notify_on_new_experience_ai on public.experiences;
create trigger notify_on_new_experience_ai after insert on public.experiences
  for each row execute function public.tg_notify_on_new_experience();

-- Realtime (ignore if already published)
do $$
begin
  alter publication supabase_realtime add table public.notifications;
exception when duplicate_object then
  null;
when undefined_object then
  null;
end
$$;

-- Completions trigger (counts + watchlist fan-out)
create or replace function public.tg_experience_completions_counts()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update public.profiles
      set completion_count = completion_count + 1, updated_at = now()
      where id = new.user_id;
    update public.experiences
      set completion_count = completion_count + 1
      where id = new.experience_id;
    insert into public.notifications (user_id, actor_id, type, reference_id)
    select f.follower_id, new.user_id, 'watchlist'::public.notification_type, new.experience_id
    from public.follows f
    where f.following_id = new.user_id and f.follower_id <> new.user_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.profiles
      set completion_count = greatest(completion_count - 1, 0), updated_at = now()
      where id = old.user_id;
    update public.experiences
      set completion_count = greatest(completion_count - 1, 0)
      where id = old.experience_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists experience_completions_counts_ai on public.experience_completions;
create trigger experience_completions_counts_ai after insert on public.experience_completions
  for each row execute function public.tg_experience_completions_counts();
drop trigger if exists experience_completions_counts_ad on public.experience_completions;
create trigger experience_completions_counts_ad after delete on public.experience_completions
  for each row execute function public.tg_experience_completions_counts();

-- ---------------------------------------------------------------------------
-- places
-- ---------------------------------------------------------------------------
create table if not exists public.places (
  id text primary key,
  name text not null,
  basic_category text not null,
  latitude double precision not null,
  longitude double precision not null,
  city text not null default 'Berkeley',
  image_urls text[] not null default '{}',
  stops text[] not null default '{}',
  created_at timestamptz not null default now()
);

alter table public.places add column if not exists city text not null default 'Berkeley';
alter table public.places add column if not exists image_urls text[] not null default '{}';
alter table public.places add column if not exists stops text[] not null default '{}';

create or replace function public.stable_uuid(raw text)
returns uuid language sql immutable as $$
  select case
    when raw ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then raw::uuid
    else (
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
create index if not exists idx_places_coordinates on public.places (latitude, longitude);
create index if not exists idx_places_category on public.places (basic_category);
create index if not exists idx_places_city on public.places (city);

alter table public.places enable row level security;

drop policy if exists "Allow public read access" on public.places;
drop policy if exists "Places are publicly readable" on public.places;
drop policy if exists "Allow service role write access" on public.places;
create policy "Places are publicly readable"
  on public.places for select using (true);

grant select on public.places to anon, authenticated;

-- ---------------------------------------------------------------------------
-- stops (normalized)
-- ---------------------------------------------------------------------------
create table if not exists public.stops (
  id uuid primary key default gen_random_uuid(),
  experience_id uuid not null references public.experiences (id) on delete cascade,
  order_index int not null default 0,
  name text not null,
  description text not null default '',
  creator_notes text not null default '',
  latitude double precision,
  longitude double precision,
  place_id text,
  recommended_time text,
  duration_minutes int not null default 30,
  emoji text,
  created_at timestamptz not null default now(),
  unique (experience_id, order_index)
);

create index if not exists idx_stops_experience_order on public.stops (experience_id, order_index);

alter table public.stops enable row level security;

drop policy if exists "Stops are publicly readable" on public.stops;
create policy "Stops are publicly readable"
  on public.stops for select using (true);

drop policy if exists "Creators can insert stops" on public.stops;
create policy "Creators can insert stops"
  on public.stops for insert
  with check (exists (
    select 1 from public.experiences e where e.id = experience_id and e.user_id = auth.uid()
  ));

drop policy if exists "Creators can update stops" on public.stops;
create policy "Creators can update stops"
  on public.stops for update
  using (exists (
    select 1 from public.experiences e where e.id = experience_id and e.user_id = auth.uid()
  ));

drop policy if exists "Creators can delete stops" on public.stops;
create policy "Creators can delete stops"
  on public.stops for delete
  using (exists (
    select 1 from public.experiences e where e.id = experience_id and e.user_id = auth.uid()
  ));

grant select on public.stops to anon, authenticated;
grant insert, update, delete on public.stops to authenticated;

-- ---------------------------------------------------------------------------
-- likes + comments
-- ---------------------------------------------------------------------------
create table if not exists public.experience_likes (
  user_id uuid not null references public.profiles (id) on delete cascade,
  experience_id uuid not null references public.experiences (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, experience_id)
);

create index if not exists idx_experience_likes_experience on public.experience_likes (experience_id);
create index if not exists idx_experience_likes_user on public.experience_likes (user_id, created_at desc);

alter table public.experience_likes enable row level security;

drop policy if exists "Likes are publicly readable" on public.experience_likes;
create policy "Likes are publicly readable"
  on public.experience_likes for select using (true);

drop policy if exists "Users can like experiences" on public.experience_likes;
create policy "Users can like experiences"
  on public.experience_likes for insert with check (auth.uid() = user_id);

drop policy if exists "Users can unlike experiences" on public.experience_likes;
create policy "Users can unlike experiences"
  on public.experience_likes for delete using (auth.uid() = user_id);

grant select on public.experience_likes to anon;
grant select, insert, delete on public.experience_likes to authenticated;

create or replace function public.tg_experience_likes_counts()
returns trigger language plpgsql security definer set search_path = public as $$
declare owner_id uuid;
begin
  if tg_op = 'INSERT' then
    update public.experiences set like_count = like_count + 1
      where id = new.experience_id returning user_id into owner_id;
    perform public.insert_notification(owner_id, new.user_id, 'like', new.experience_id);
    return new;
  elsif tg_op = 'DELETE' then
    update public.experiences set like_count = greatest(like_count - 1, 0)
      where id = old.experience_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists experience_likes_counts_ai on public.experience_likes;
create trigger experience_likes_counts_ai after insert on public.experience_likes
  for each row execute function public.tg_experience_likes_counts();
drop trigger if exists experience_likes_counts_ad on public.experience_likes;
create trigger experience_likes_counts_ad after delete on public.experience_likes
  for each row execute function public.tg_experience_likes_counts();

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  experience_id uuid not null references public.experiences (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  parent_id uuid references public.comments (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_comments_experience_created on public.comments (experience_id, created_at desc);
create index if not exists idx_comments_author on public.comments (author_id);

alter table public.comments enable row level security;

drop policy if exists "Comments are publicly readable" on public.comments;
create policy "Comments are publicly readable"
  on public.comments for select using (true);

drop policy if exists "Users can comment" on public.comments;
create policy "Users can comment"
  on public.comments for insert with check (auth.uid() = author_id);

drop policy if exists "Users can edit their comments" on public.comments;
create policy "Users can edit their comments"
  on public.comments for update using (auth.uid() = author_id);

drop policy if exists "Users can delete their comments" on public.comments;
create policy "Users can delete their comments"
  on public.comments for delete using (auth.uid() = author_id);

grant select on public.comments to anon;
grant select, insert, update, delete on public.comments to authenticated;

create or replace function public.tg_comments_counts()
returns trigger language plpgsql security definer set search_path = public as $$
declare owner_id uuid;
begin
  if tg_op = 'INSERT' then
    update public.experiences set comment_count = comment_count + 1
      where id = new.experience_id returning user_id into owner_id;
    perform public.insert_notification(owner_id, new.author_id, 'comment', new.experience_id);
    return new;
  elsif tg_op = 'DELETE' then
    update public.experiences set comment_count = greatest(comment_count - 1, 0)
      where id = old.experience_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists comments_counts_ai on public.comments;
create trigger comments_counts_ai after insert on public.comments
  for each row execute function public.tg_comments_counts();
drop trigger if exists comments_counts_ad on public.comments;
create trigger comments_counts_ad after delete on public.comments
  for each row execute function public.tg_comments_counts();

-- ---------------------------------------------------------------------------
-- moderation
-- ---------------------------------------------------------------------------
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  experience_id uuid references public.experiences (id) on delete cascade,
  comment_id uuid references public.comments (id) on delete cascade,
  reported_user_id uuid references public.profiles (id) on delete cascade,
  reason text not null check (reason in (
    'spam', 'inappropriate', 'harassment', 'misinformation', 'copyright', 'other'
  )),
  details text check (details is null or char_length(details) <= 500),
  status text not null default 'open' check (status in ('open', 'reviewed', 'actioned', 'dismissed')),
  created_at timestamptz not null default now(),
  constraint reports_single_target check (
    (experience_id is not null)::int
    + (comment_id is not null)::int
    + (reported_user_id is not null)::int = 1
  )
);

create index if not exists idx_reports_status_created on public.reports (status, created_at desc);

alter table public.reports enable row level security;

drop policy if exists "Users can file reports" on public.reports;
create policy "Users can file reports"
  on public.reports for insert with check (auth.uid() = reporter_id);

drop policy if exists "Users can read their own reports" on public.reports;
create policy "Users can read their own reports"
  on public.reports for select using (auth.uid() = reporter_id);

grant select, insert on public.reports to authenticated;

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_no_self check (blocker_id <> blocked_id)
);

create index if not exists idx_blocks_blocked on public.blocks (blocked_id);

alter table public.blocks enable row level security;

drop policy if exists "Users can read their own blocks" on public.blocks;
create policy "Users can read their own blocks"
  on public.blocks for select using (auth.uid() = blocker_id);

drop policy if exists "Users can block others" on public.blocks;
create policy "Users can block others"
  on public.blocks for insert with check (auth.uid() = blocker_id);

drop policy if exists "Users can unblock" on public.blocks;
create policy "Users can unblock"
  on public.blocks for delete using (auth.uid() = blocker_id);

grant select, insert, delete on public.blocks to authenticated;

create or replace function public.tg_blocks_remove_follows()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.follows
  where (follower_id = new.blocker_id and following_id = new.blocked_id)
     or (follower_id = new.blocked_id and following_id = new.blocker_id);
  return new;
end;
$$;

drop trigger if exists blocks_remove_follows_ai on public.blocks;
create trigger blocks_remove_follows_ai after insert on public.blocks
  for each row execute function public.tg_blocks_remove_follows();

-- ---------------------------------------------------------------------------
-- device tokens (APNs)
-- ---------------------------------------------------------------------------
create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  platform text not null default 'ios' check (platform in ('ios')),
  environment text not null default 'production' check (environment in ('production', 'sandbox')),
  updated_at timestamptz not null default now()
);

create index if not exists idx_device_tokens_user on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

drop policy if exists "Users manage their own device tokens" on public.device_tokens;
create policy "Users manage their own device tokens"
  on public.device_tokens for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

grant select, insert, update, delete on public.device_tokens to authenticated;

-- ---------------------------------------------------------------------------
-- popups (optional table — create if missing, then lock down writes)
-- ---------------------------------------------------------------------------
create table if not exists public.popups (
  id uuid primary key default gen_random_uuid(),
  event_name text not null,
  address text not null default 'Berkeley, CA',
  start_time timestamptz,
  end_time timestamptz,
  created_at timestamptz not null default now()
);

alter table public.popups enable row level security;

drop policy if exists "Popups are publicly readable" on public.popups;
create policy "Popups are publicly readable"
  on public.popups for select using (true);

drop policy if exists "Users can insert popups" on public.popups;
revoke insert on public.popups from anon, authenticated;

grant select on public.popups to anon, authenticated;

delete from public.popups a
using public.popups b
where a.ctid < b.ctid
  and a.event_name = b.event_name
  and a.start_time is not distinct from b.start_time;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'popups_event_start_unique') then
    alter table public.popups
      add constraint popups_event_start_unique unique (event_name, start_time);
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- reserved usernames
-- ---------------------------------------------------------------------------
create table if not exists public.reserved_usernames (
  username text primary key
);

alter table public.reserved_usernames enable row level security;

drop policy if exists "Reserved usernames are publicly readable" on public.reserved_usernames;
create policy "Reserved usernames are publicly readable"
  on public.reserved_usernames for select using (true);

grant select on public.reserved_usernames to anon, authenticated;

insert into public.reserved_usernames (username) values
  ('admin'), ('support'), ('trav'), ('api'), ('help'), ('root'), ('system'),
  ('moderator'), ('mod'), ('staff'), ('official'), ('settings'), ('login'), ('signup')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- storage buckets
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', true, 5242880,
   array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']),
  ('experiences', 'experiences', true, 10485760,
   array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']),
  ('completions', 'completions', true, 10485760,
   array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Avatar images are publicly accessible" on storage.objects;
drop policy if exists "Users can upload their own avatar" on storage.objects;
drop policy if exists "Users can update their own avatar" on storage.objects;
drop policy if exists "Users can delete their own avatar" on storage.objects;
drop policy if exists "Experience media is publicly accessible" on storage.objects;
drop policy if exists "Users can upload experience media" on storage.objects;
drop policy if exists "Users can update their experience media" on storage.objects;
drop policy if exists "Users can delete their experience media" on storage.objects;
drop policy if exists "Completion photos are publicly accessible" on storage.objects;
drop policy if exists "Users can upload completion photos" on storage.objects;
drop policy if exists "Users can delete their completion photos" on storage.objects;

create policy "Avatar images are publicly accessible"
on storage.objects for select using (bucket_id = 'avatars');

create policy "Users can upload their own avatar"
on storage.objects for insert to authenticated
with check (bucket_id = 'avatars' and lower((storage.foldername(name))[1]) = lower(auth.uid()::text));

create policy "Users can update their own avatar"
on storage.objects for update to authenticated
using (bucket_id = 'avatars' and lower((storage.foldername(name))[1]) = lower(auth.uid()::text))
with check (bucket_id = 'avatars' and lower((storage.foldername(name))[1]) = lower(auth.uid()::text));

create policy "Users can delete their own avatar"
on storage.objects for delete to authenticated
using (bucket_id = 'avatars' and lower((storage.foldername(name))[1]) = lower(auth.uid()::text));

create policy "Experience media is publicly accessible"
on storage.objects for select using (bucket_id = 'experiences');

create policy "Users can upload experience media"
on storage.objects for insert to authenticated
with check (bucket_id = 'experiences' and lower((storage.foldername(name))[1]) = lower(auth.uid()::text));

create policy "Users can update their experience media"
on storage.objects for update to authenticated
using (bucket_id = 'experiences' and lower((storage.foldername(name))[1]) = lower(auth.uid()::text))
with check (bucket_id = 'experiences' and lower((storage.foldername(name))[1]) = lower(auth.uid()::text));

create policy "Users can delete their experience media"
on storage.objects for delete to authenticated
using (bucket_id = 'experiences' and lower((storage.foldername(name))[1]) = lower(auth.uid()::text));

create policy "Completion photos are publicly accessible"
on storage.objects for select using (bucket_id = 'completions');

create policy "Users can upload completion photos"
on storage.objects for insert to authenticated
with check (bucket_id = 'completions' and lower((storage.foldername(name))[1]) = lower(auth.uid()::text));

create policy "Users can delete their completion photos"
on storage.objects for delete to authenticated
using (bucket_id = 'completions' and lower((storage.foldername(name))[1]) = lower(auth.uid()::text));

-- ---------------------------------------------------------------------------
-- final counter recompute
-- ---------------------------------------------------------------------------
update public.profiles p
set follower_count  = (select count(*) from public.follows f where f.following_id = p.id),
    following_count = (select count(*) from public.follows f where f.follower_id = p.id);

update public.cities c
set experience_count = (select count(*) from public.experiences e where e.city_id = c.id and e.is_published = true),
    creator_count = (select count(distinct e.user_id) from public.experiences e where e.city_id = c.id and e.is_published = true);

-- Done.
