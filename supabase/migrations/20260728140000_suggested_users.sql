-- Contact-hash matching + suggested-users RPC for Instagram-style discovery.

create table if not exists public.profile_contact_hashes (
  user_id uuid not null references public.profiles (id) on delete cascade,
  hash text not null,
  kind text not null check (kind in ('phone', 'email')),
  created_at timestamptz not null default now(),
  primary key (user_id, hash)
);

create index if not exists idx_profile_contact_hashes_hash
  on public.profile_contact_hashes (hash);

alter table public.profile_contact_hashes enable row level security;

drop policy if exists "Users can read own contact hashes" on public.profile_contact_hashes;
create policy "Users can read own contact hashes"
  on public.profile_contact_hashes for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own contact hashes" on public.profile_contact_hashes;
create policy "Users can insert own contact hashes"
  on public.profile_contact_hashes for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own contact hashes" on public.profile_contact_hashes;
create policy "Users can update own contact hashes"
  on public.profile_contact_hashes for update
  using (auth.uid() = user_id);

drop policy if exists "Users can delete own contact hashes" on public.profile_contact_hashes;
create policy "Users can delete own contact hashes"
  on public.profile_contact_hashes for delete
  using (auth.uid() = user_id);

grant select, insert, update, delete on public.profile_contact_hashes to authenticated;

-- Replace the caller's contact hashes in one round trip.
create or replace function public.sync_contact_hashes(p_hashes jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  delete from public.profile_contact_hashes where user_id = uid;

  insert into public.profile_contact_hashes (user_id, hash, kind)
  select
    uid,
    trim(both from (item->>'hash')),
    trim(both from (item->>'kind'))
  from jsonb_array_elements(coalesce(p_hashes, '[]'::jsonb)) as item
  where coalesce(item->>'hash', '') <> ''
    and coalesce(item->>'kind', '') in ('phone', 'email')
  on conflict (user_id, hash) do update
    set kind = excluded.kind;
end;
$$;

revoke all on function public.sync_contact_hashes(jsonb) from public;
grant execute on function public.sync_contact_hashes(jsonb) to authenticated;

-- Ranked suggestions: contact matches, then mutual follows, then popular.
create or replace function public.fetch_suggested_users(p_limit int default 20)
returns table (
  id uuid,
  username text,
  display_name text,
  bio text,
  avatar_url text,
  home_city_id uuid,
  follower_count integer,
  following_count integer,
  experience_count integer,
  completion_count integer,
  is_verified boolean,
  selected_vibes text[],
  onboarding_location text,
  source text,
  mutual_count integer,
  sample_mutual_name text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  lim int := greatest(1, least(coalesce(p_limit, 20), 50));
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  return query
  with
  blocked as (
    select b.blocked_id as other_id
    from public.blocks b
    where b.blocker_id = uid
    union
    select b.blocker_id as other_id
    from public.blocks b
    where b.blocked_id = uid
  ),
  already_following as (
    select f.following_id
    from public.follows f
    where f.follower_id = uid
  ),
  contact_hits as (
    select distinct other.user_id as suggested_id
    from public.profile_contact_hashes mine
    join public.profile_contact_hashes other
      on other.hash = mine.hash
     and other.user_id <> mine.user_id
    where mine.user_id = uid
  ),
  mutuals as (
    select
      f2.following_id as suggested_id,
      count(*)::int as mutual_count,
      (array_agg(p.display_name order by p.display_name))[1] as sample_mutual_name
    from public.follows f1
    join public.follows f2
      on f2.follower_id = f1.following_id
    join public.profiles p
      on p.id = f1.following_id
    where f1.follower_id = uid
      and f2.following_id <> uid
      and f2.following_id not in (select following_id from already_following)
      and f2.following_id not in (select other_id from blocked)
    group by f2.following_id
  ),
  candidates as (
    select
      p.id,
      p.username,
      p.display_name,
      p.bio,
      p.avatar_url,
      p.home_city_id,
      p.follower_count,
      p.following_count,
      p.experience_count,
      p.completion_count,
      p.is_verified,
      p.selected_vibes,
      p.onboarding_location,
      case
        when c.suggested_id is not null then 'contact'
        when m.suggested_id is not null then 'mutual'
        else 'popular'
      end as source,
      coalesce(m.mutual_count, 0) as mutual_count,
      m.sample_mutual_name as sample_mutual_name,
      case
        when c.suggested_id is not null then 0
        when m.suggested_id is not null then 1
        else 2
      end as rank_bucket
    from public.profiles p
    left join contact_hits c on c.suggested_id = p.id
    left join mutuals m on m.suggested_id = p.id
    where p.id <> uid
      and p.id not in (select following_id from already_following)
      and p.id not in (select other_id from blocked)
      and (
        c.suggested_id is not null
        or m.suggested_id is not null
        or p.follower_count > 0
      )
  )
  select
    candidates.id,
    candidates.username,
    candidates.display_name,
    candidates.bio,
    candidates.avatar_url,
    candidates.home_city_id,
    candidates.follower_count,
    candidates.following_count,
    candidates.experience_count,
    candidates.completion_count,
    candidates.is_verified,
    candidates.selected_vibes,
    candidates.onboarding_location,
    candidates.source,
    candidates.mutual_count,
    candidates.sample_mutual_name
  from candidates
  order by
    candidates.rank_bucket asc,
    candidates.mutual_count desc,
    candidates.follower_count desc,
    candidates.display_name asc
  limit lim;
end;
$$;

revoke all on function public.fetch_suggested_users(int) from public;
grant execute on function public.fetch_suggested_users(int) to authenticated;
