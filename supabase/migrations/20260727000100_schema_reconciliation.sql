-- Schema reconciliation: converge the live database (which accumulated ad-hoc
-- tables `followers` and `saved_experiences`) onto the canonical migrated
-- tables `follows` and `experience_saves`, normalize `experiences.image`,
-- lock down open policies, and rebind all triggers to canonical tables.
--
-- Safe to run repeatedly (idempotent) and safe on databases that never had
-- the ad-hoc tables.

-- ---------------------------------------------------------------------------
-- 1. Follows: ensure canonical table exists, merge `followers`, then drop it
-- ---------------------------------------------------------------------------
-- Live DBs may only have the ad-hoc `followers` table (never applied
-- `20260721200000_profile_social.sql`). Create `follows` first so the merge
-- cannot fail with "relation does not exist".
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

-- ---------------------------------------------------------------------------
-- 2. Saves: merge `saved_experiences` into `experience_saves`, then drop
-- ---------------------------------------------------------------------------
create table if not exists public.experience_saves (
  user_id uuid not null references public.profiles (id) on delete cascade,
  experience_id uuid not null references public.experiences (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, experience_id)
);

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

drop policy if exists "Users can unsave experiences" on public.experience_saves;
create policy "Users can unsave experiences"
  on public.experience_saves for delete
  using (auth.uid() = user_id);

grant select on public.experience_saves to anon;
grant select, insert, delete on public.experience_saves to authenticated;

-- Denormalized counters may be missing if profile_social never ran on this DB.
alter table public.experiences
  add column if not exists save_count integer not null default 0;
alter table public.experiences
  add column if not exists completion_count integer not null default 0;

-- Recompute counters from the merged canonical tables.
update public.experiences e
set save_count = (select count(*) from public.experience_saves s where s.experience_id = e.id);

do $$
begin
  if to_regclass('public.experience_completions') is not null then
    update public.experiences e
    set completion_count = (
      select count(*) from public.experience_completions c where c.experience_id = e.id
    );
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 3. Experiences: description default, publish flag, image normalized to jsonb
-- ---------------------------------------------------------------------------
alter table public.experiences
  alter column description set default '';

-- Replaces the '__trav_bookmark__' description sentinel: shadow rows created
-- to satisfy FK constraints when bookmarking feed places are now explicitly
-- unpublished, and every read path filters on is_published.
alter table public.experiences
  add column if not exists is_published boolean not null default true;

update public.experiences
set is_published = false, description = ''
where description = '__trav_bookmark__';

create index if not exists idx_experiences_published_created
  on public.experiences (created_at desc)
  where is_published = true;

-- `image` has been written both as a single text URL and as a text[] of URLs.
-- Normalize to jsonb, which accepts both shapes (the client decodes either).
do $$
declare
  col_type text;
begin
  select data_type into col_type
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'experiences'
    and column_name = 'image';

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

-- ---------------------------------------------------------------------------
-- 4. Rebind triggers to canonical tables (drop table CASCADE removed them)
-- ---------------------------------------------------------------------------

-- Follow counts (define here — may never have been created on this DB).
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

-- Follow / save notification triggers only if notification helpers already exist
-- (created by 20260725200000_create_notifications.sql). Skip gracefully otherwise.
do $$
begin
  if to_regprocedure('public.tg_notify_on_follow()') is not null then
    drop trigger if exists notify_on_follow_ai on public.follows;
    create trigger notify_on_follow_ai
      after insert on public.follows
      for each row execute function public.tg_notify_on_follow();
  end if;

  if to_regprocedure('public.tg_notify_on_experience_save()') is not null then
    drop trigger if exists notify_on_experience_save_ai on public.experience_saves;
    create trigger notify_on_experience_save_ai
      after insert on public.experience_saves
      for each row execute function public.tg_notify_on_experience_save();
  end if;
end
$$;

-- Save counts
create or replace function public.tg_experience_saves_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.experiences set save_count = save_count + 1
      where id = new.experience_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.experiences set save_count = greatest(save_count - 1, 0)
      where id = old.experience_id;
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

-- New-experience fan-out: only when notifications table exists.
create or replace function public.tg_notify_on_new_experience()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if to_regclass('public.notifications') is null then
    return new;
  end if;

  -- Skip unpublished rows (drafts and place-bookmark shadow rows).
  if new.is_published = false then
    return new;
  end if;

  insert into public.notifications (user_id, actor_id, type, reference_id)
  select f.follower_id, new.user_id, 'new_experience'::public.notification_type, new.id
  from public.follows f
  where f.following_id = new.user_id
    and f.follower_id <> new.user_id;

  return new;
end;
$$;

drop trigger if exists notify_on_new_experience_ai on public.experiences;
create trigger notify_on_new_experience_ai
  after insert on public.experiences
  for each row execute function public.tg_notify_on_new_experience();

-- Completion (watchlist) counts + optional follower fan-out.
create or replace function public.tg_experience_completions_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.profiles
      set completion_count = completion_count + 1, updated_at = now()
      where id = new.user_id;
    update public.experiences
      set completion_count = completion_count + 1
      where id = new.experience_id;

    if to_regclass('public.notifications') is not null
       and exists (
         select 1 from pg_enum e
         join pg_type t on t.oid = e.enumtypid
         where t.typname = 'notification_type' and e.enumlabel = 'watchlist'
       ) then
      insert into public.notifications (user_id, actor_id, type, reference_id)
      select f.follower_id, new.user_id, 'watchlist'::public.notification_type, new.experience_id
      from public.follows f
      where f.following_id = new.user_id
        and f.follower_id <> new.user_id;
    end if;

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

do $$
begin
  if to_regclass('public.experience_completions') is not null then
    drop trigger if exists experience_completions_counts_ai on public.experience_completions;
    create trigger experience_completions_counts_ai
      after insert on public.experience_completions
      for each row execute function public.tg_experience_completions_counts();

    drop trigger if exists experience_completions_counts_ad on public.experience_completions;
    create trigger experience_completions_counts_ad
      after delete on public.experience_completions
      for each row execute function public.tg_experience_completions_counts();
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 5. Lock down popups (was: anyone can insert)
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.popups') is null then
    return;
  end if;

  execute 'drop policy if exists "Users can insert popups" on public.popups';
  execute 'revoke insert on public.popups from anon, authenticated';

  -- Deduplicate before adding the unique constraint the pipeline relies on.
  delete from public.popups a
  using public.popups b
  where a.ctid < b.ctid
    and a.event_name = b.event_name
    and a.start_time is not distinct from b.start_time;

  if not exists (
    select 1 from pg_constraint where conname = 'popups_event_start_unique'
  ) then
    alter table public.popups
      add constraint popups_event_start_unique unique (event_name, start_time);
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 6. Reserved usernames: enable RLS (read-only reference data)
-- ---------------------------------------------------------------------------
alter table public.reserved_usernames enable row level security;

drop policy if exists "Reserved usernames are publicly readable" on public.reserved_usernames;
create policy "Reserved usernames are publicly readable"
  on public.reserved_usernames for select using (true);

grant select on public.reserved_usernames to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. Recompute profile counters from canonical tables
-- ---------------------------------------------------------------------------
update public.profiles p
set follower_count  = (select count(*) from public.follows f where f.following_id = p.id),
    following_count = (select count(*) from public.follows f where f.follower_id = p.id);
