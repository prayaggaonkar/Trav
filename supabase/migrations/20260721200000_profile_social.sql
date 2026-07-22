-- Profile social graph, engagement, and username integrity.
-- Supports follows, saves, completions, avatar storage path conventions,
-- and denormalized counters kept in sync via triggers.

-- ---------------------------------------------------------------------------
-- Experiences: align with app writes (image + engagement counters)
-- ---------------------------------------------------------------------------
alter table public.experiences
  add column if not exists image text;

alter table public.experiences
  add column if not exists save_count integer not null default 0;

alter table public.experiences
  add column if not exists completion_count integer not null default 0;

-- ---------------------------------------------------------------------------
-- Profiles: home city display name + username integrity
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists home_city_name text;

-- Normalize usernames to lowercase going forward.
update public.profiles set username = lower(username) where username <> lower(username);

-- Sanitize any legacy usernames that would fail the new format check.
update public.profiles
set username = regexp_replace(lower(username), '[^a-z0-9._]', '', 'g')
where username !~ '^[a-z0-9._]+$';

update public.profiles
set username = left(username || substr(replace(id::text, '-', ''), 1, 4), 30)
where char_length(username) < 3;

create unique index if not exists idx_profiles_username_lower
  on public.profiles (lower(username));

alter table public.profiles
  drop constraint if exists profiles_username_format;

alter table public.profiles
  add constraint profiles_username_format
  check (
    char_length(username) between 3 and 30
    and username ~ '^[a-z0-9._]+$'
  );

alter table public.profiles
  drop constraint if exists profiles_bio_length;

alter table public.profiles
  add constraint profiles_bio_length
  check (bio is null or char_length(bio) <= 160);

alter table public.profiles
  drop constraint if exists profiles_display_name_length;

alter table public.profiles
  add constraint profiles_display_name_length
  check (char_length(display_name) between 1 and 50);

-- ---------------------------------------------------------------------------
-- Reserved usernames
-- ---------------------------------------------------------------------------
create table if not exists public.reserved_usernames (
  username text primary key
);

insert into public.reserved_usernames (username) values
  ('admin'), ('support'), ('trav'), ('api'), ('help'), ('root'),
  ('system'), ('moderator'), ('mod'), ('staff'), ('official'),
  ('null'), ('undefined'), ('me'), ('you'), ('settings'), ('edit'),
  ('login'), ('signup'), ('auth'), ('www'), ('about'), ('privacy'),
  ('terms'), ('status'), ('billing'), ('payment')
on conflict do nothing;

create or replace function public.is_username_available(candidate text, excluding_user_id uuid default null)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized text := lower(trim(candidate));
begin
  if normalized is null
     or char_length(normalized) < 3
     or char_length(normalized) > 30
     or normalized !~ '^[a-z0-9._]+$' then
    return false;
  end if;

  if exists (select 1 from public.reserved_usernames where username = normalized) then
    return false;
  end if;

  if exists (
    select 1 from public.profiles
    where lower(username) = normalized
      and (excluding_user_id is null or id <> excluding_user_id)
  ) then
    return false;
  end if;

  return true;
end;
$$;

grant execute on function public.is_username_available(text, uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Follows
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
  on public.follows for insert
  with check (auth.uid() = follower_id);

drop policy if exists "Users can unfollow" on public.follows;
create policy "Users can unfollow"
  on public.follows for delete
  using (auth.uid() = follower_id);

grant select on public.follows to anon;
grant select, insert, delete on public.follows to authenticated;

create or replace function public.tg_follows_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.profiles set following_count = following_count + 1, updated_at = now()
      where id = new.follower_id;
    update public.profiles set follower_count = follower_count + 1, updated_at = now()
      where id = new.following_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.profiles set following_count = greatest(following_count - 1, 0), updated_at = now()
      where id = old.follower_id;
    update public.profiles set follower_count = greatest(follower_count - 1, 0), updated_at = now()
      where id = old.following_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists follows_counts_ai on public.follows;
create trigger follows_counts_ai
  after insert on public.follows
  for each row execute function public.tg_follows_counts();

drop trigger if exists follows_counts_ad on public.follows;
create trigger follows_counts_ad
  after delete on public.follows
  for each row execute function public.tg_follows_counts();

-- ---------------------------------------------------------------------------
-- Experience saves
-- ---------------------------------------------------------------------------
create table if not exists public.experience_saves (
  user_id uuid not null references public.profiles (id) on delete cascade,
  experience_id uuid not null references public.experiences (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, experience_id)
);

create index if not exists idx_experience_saves_user
  on public.experience_saves (user_id, created_at desc);
create index if not exists idx_experience_saves_experience
  on public.experience_saves (experience_id);

alter table public.experience_saves enable row level security;

drop policy if exists "Saves are publicly readable" on public.experience_saves;
create policy "Saves are publicly readable"
  on public.experience_saves for select using (true);

drop policy if exists "Users can save experiences" on public.experience_saves;
create policy "Users can save experiences"
  on public.experience_saves for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can unsaved experiences" on public.experience_saves;
create policy "Users can unsaved experiences"
  on public.experience_saves for delete
  using (auth.uid() = user_id);

grant select on public.experience_saves to anon;
grant select, insert, delete on public.experience_saves to authenticated;

create or replace function public.tg_experience_saves_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
create trigger experience_saves_counts_ai
  after insert on public.experience_saves
  for each row execute function public.tg_experience_saves_counts();

drop trigger if exists experience_saves_counts_ad on public.experience_saves;
create trigger experience_saves_counts_ad
  after delete on public.experience_saves
  for each row execute function public.tg_experience_saves_counts();

-- ---------------------------------------------------------------------------
-- Experience completions
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
  on public.experience_completions for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their completions" on public.experience_completions;
create policy "Users can update their completions"
  on public.experience_completions for update
  using (auth.uid() = user_id);

drop policy if exists "Users can delete their completions" on public.experience_completions;
create policy "Users can delete their completions"
  on public.experience_completions for delete
  using (auth.uid() = user_id);

grant select on public.experience_completions to anon;
grant select, insert, update, delete on public.experience_completions to authenticated;

create or replace function public.tg_experience_completions_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.experiences
      set completion_count = completion_count + 1
      where id = new.experience_id;
    update public.profiles
      set completion_count = completion_count + 1, updated_at = now()
      where id = new.user_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.experiences
      set completion_count = greatest(completion_count - 1, 0)
      where id = old.experience_id;
    update public.profiles
      set completion_count = greatest(completion_count - 1, 0), updated_at = now()
      where id = old.user_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists experience_completions_counts_ai on public.experience_completions;
create trigger experience_completions_counts_ai
  after insert on public.experience_completions
  for each row execute function public.tg_experience_completions_counts();

drop trigger if exists experience_completions_counts_ad on public.experience_completions;
create trigger experience_completions_counts_ad
  after delete on public.experience_completions
  for each row execute function public.tg_experience_completions_counts();

-- Keep profiles.experience_count in sync with published experiences.
create or replace function public.tg_experiences_creator_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.profiles
      set experience_count = experience_count + 1, updated_at = now()
      where id = new.user_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.profiles
      set experience_count = greatest(experience_count - 1, 0), updated_at = now()
      where id = old.user_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists experiences_creator_count_ai on public.experiences;
create trigger experiences_creator_count_ai
  after insert on public.experiences
  for each row execute function public.tg_experiences_creator_count();

drop trigger if exists experiences_creator_count_ad on public.experiences;
create trigger experiences_creator_count_ad
  after delete on public.experiences
  for each row execute function public.tg_experiences_creator_count();

-- Touch updated_at on profile edits.
create or replace function public.tg_profiles_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  new.username = lower(new.username);
  return new;
end;
$$;

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.tg_profiles_updated_at();
