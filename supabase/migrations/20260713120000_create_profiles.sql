-- Profiles table backing SupabaseAuthRepository / the app's `Profile` model.
-- See docs/DATABASE_SCHEMA.md for the full schema and RLS summary.

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text unique not null,
  display_name text not null,
  bio text,
  avatar_url text,
  home_city_id uuid, -- FK to public.cities(id) once that table exists
  follower_count integer not null default 0,
  following_count integer not null default 0,
  experience_count integer not null default 0,
  completion_count integer not null default 0,
  is_verified boolean not null default false,
  selected_vibes text[] not null default '{}',
  onboarding_location text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_profiles_username on public.profiles (username);

alter table public.profiles enable row level security;

-- Public read access (profiles are viewable by anyone, per docs/DATABASE_SCHEMA.md).
create policy "Profiles are publicly readable"
  on public.profiles for select
  using (true);

-- Users may only create/update their own profile row.
create policy "Users can insert their own profile"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "Users can update their own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- Explicit grants (Supabase projects normally default these already, but this
-- makes the migration self-contained regardless of project defaults).
grant select on public.profiles to anon;
grant select, insert, update on public.profiles to authenticated;
