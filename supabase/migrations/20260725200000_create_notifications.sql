-- In-app notifications: follow, save, and new_experience fan-out.
-- Triggers attach to whichever follow table exists (`followers` preferred — matches the iOS client —
-- falling back to `follows` from earlier migrations).

-- ---------------------------------------------------------------------------
-- Enum + table
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'notification_type') then
    create type public.notification_type as enum (
      'follow',
      'save',
      'new_experience'
    );
  end if;
end
$$;

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
  on public.notifications (user_id)
  where is_read = false;

alter table public.notifications enable row level security;

drop policy if exists "Users can read their notifications" on public.notifications;
create policy "Users can read their notifications"
  on public.notifications for select
  using (auth.uid() = user_id);

drop policy if exists "Users can update their notifications" on public.notifications;
create policy "Users can update their notifications"
  on public.notifications for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- No client INSERT/DELETE — rows are created by security-definer triggers only.
grant select, update on public.notifications to authenticated;

-- ---------------------------------------------------------------------------
-- Helper: insert one notification (skips self-notifications)
-- ---------------------------------------------------------------------------
create or replace function public.insert_notification(
  p_user_id uuid,
  p_actor_id uuid,
  p_type public.notification_type,
  p_reference_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user_id is null or p_actor_id is null then
    return;
  end if;
  if p_user_id = p_actor_id then
    return;
  end if;

  insert into public.notifications (user_id, actor_id, type, reference_id)
  values (p_user_id, p_actor_id, p_type, p_reference_id);
end;
$$;

revoke all on function public.insert_notification(uuid, uuid, public.notification_type, uuid) from public;

-- ---------------------------------------------------------------------------
-- Follow → notify the followed user
-- ---------------------------------------------------------------------------
create or replace function public.tg_notify_on_follow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.insert_notification(
    new.following_id,
    new.follower_id,
    'follow'::public.notification_type,
    new.follower_id
  );
  return new;
end;
$$;

do $$
declare
  follow_table text;
begin
  if to_regclass('public.followers') is not null then
    follow_table := 'followers';
  elsif to_regclass('public.follows') is not null then
    follow_table := 'follows';
  else
    raise notice 'No follows/followers table — skipping follow notification trigger';
    return;
  end if;

  execute format('drop trigger if exists notify_on_follow_ai on public.%I', follow_table);
  execute format(
    'create trigger notify_on_follow_ai
       after insert on public.%I
       for each row execute function public.tg_notify_on_follow()',
    follow_table
  );
end
$$;

-- ---------------------------------------------------------------------------
-- Save → notify experience owner
-- ---------------------------------------------------------------------------
create or replace function public.tg_notify_on_experience_save()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid;
begin
  select user_id into owner_id
  from public.experiences
  where id = new.experience_id;

  if owner_id is null then
    return new;
  end if;

  perform public.insert_notification(
    owner_id,
    new.user_id,
    'save'::public.notification_type,
    new.experience_id
  );
  return new;
end;
$$;

drop trigger if exists notify_on_experience_save_ai on public.experience_saves;
create trigger notify_on_experience_save_ai
  after insert on public.experience_saves
  for each row execute function public.tg_notify_on_experience_save();

-- ---------------------------------------------------------------------------
-- New experience → fan-out to followers (skip bookmark sentinels)
-- ---------------------------------------------------------------------------
create or replace function public.tg_notify_on_new_experience()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.description = '__trav_bookmark__' then
    return new;
  end if;

  if to_regclass('public.followers') is not null then
    insert into public.notifications (user_id, actor_id, type, reference_id)
    select f.follower_id, new.user_id, 'new_experience'::public.notification_type, new.id
    from public.followers f
    where f.following_id = new.user_id
      and f.follower_id <> new.user_id;
  elsif to_regclass('public.follows') is not null then
    insert into public.notifications (user_id, actor_id, type, reference_id)
    select f.follower_id, new.user_id, 'new_experience'::public.notification_type, new.id
    from public.follows f
    where f.following_id = new.user_id
      and f.follower_id <> new.user_id;
  end if;

  return new;
end;
$$;

drop trigger if exists notify_on_new_experience_ai on public.experiences;
create trigger notify_on_new_experience_ai
  after insert on public.experiences
  for each row execute function public.tg_notify_on_new_experience();
