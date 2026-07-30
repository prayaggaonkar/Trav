-- ---------------------------------------------------------------------------
-- Ratings as a first-class object.
--
-- A rating belongs to exactly one (user, experience) pair and is the only way
-- to complete an experience: submitting a rating creates the completion row,
-- deleting it removes the completion. Averages are recomputed in the database
-- so no client ever has to maintain them.
--
-- Averages are tracked twice:
--   * average_rating           — every rating, including the creator's own
--   * community_average_rating — everyone except the creator
-- The UI greys out creator-only scores and only shows purple community scores
-- once community_rating_count > 0.
-- ---------------------------------------------------------------------------

create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  experience_id uuid not null references public.experiences (id) on delete cascade,
  -- Hexagon axis scores exactly as captured by the UI, e.g. {"Food": 8.4}.
  scores jsonb not null default '{}'::jsonb,
  disabled_categories text[] not null default '{}',
  overall_score numeric(4, 2) not null,
  review text,
  photo_urls text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ratings_unique_per_user_experience unique (user_id, experience_id),
  constraint ratings_overall_range check (overall_score >= 0 and overall_score <= 10),
  constraint ratings_scores_object check (jsonb_typeof(scores) = 'object'),
  constraint ratings_review_length check (review is null or char_length(review) <= 1000),
  constraint ratings_photo_limit check (coalesce(array_length(photo_urls, 1), 0) <= 3)
);

create index if not exists idx_ratings_experience_created
  on public.ratings (experience_id, created_at desc);
create index if not exists idx_ratings_user_created
  on public.ratings (user_id, created_at desc);

alter table public.ratings enable row level security;

drop policy if exists "Ratings are publicly readable" on public.ratings;
create policy "Ratings are publicly readable"
  on public.ratings for select using (true);

drop policy if exists "Users can create their ratings" on public.ratings;
create policy "Users can create their ratings"
  on public.ratings for insert with check (auth.uid() = user_id);

drop policy if exists "Users can update their ratings" on public.ratings;
create policy "Users can update their ratings"
  on public.ratings for update using (auth.uid() = user_id);

drop policy if exists "Users can delete their ratings" on public.ratings;
create policy "Users can delete their ratings"
  on public.ratings for delete using (auth.uid() = user_id);

grant select on public.ratings to anon;
grant select, insert, update, delete on public.ratings to authenticated;

-- ---------------------------------------------------------------------------
-- Photos
-- ---------------------------------------------------------------------------

create table if not exists public.photos (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  experience_id uuid references public.experiences (id) on delete cascade,
  rating_id uuid references public.ratings (id) on delete cascade,
  url text not null,
  order_index integer not null default 0,
  created_at timestamptz not null default now(),
  constraint photos_single_parent check (
    (experience_id is not null)::int + (rating_id is not null)::int = 1
  )
);

create index if not exists idx_photos_experience on public.photos (experience_id, order_index);
create index if not exists idx_photos_rating on public.photos (rating_id, order_index);
create index if not exists idx_photos_owner on public.photos (owner_id, created_at desc);

alter table public.photos enable row level security;

drop policy if exists "Photos are publicly readable" on public.photos;
create policy "Photos are publicly readable"
  on public.photos for select using (true);

drop policy if exists "Users can add their photos" on public.photos;
create policy "Users can add their photos"
  on public.photos for insert with check (auth.uid() = owner_id);

drop policy if exists "Users can delete their photos" on public.photos;
create policy "Users can delete their photos"
  on public.photos for delete using (auth.uid() = owner_id);

grant select on public.photos to anon;
grant select, insert, update, delete on public.photos to authenticated;

-- ---------------------------------------------------------------------------
-- Rating aggregates on experiences
-- ---------------------------------------------------------------------------

alter table public.experiences
  add column if not exists rating_count integer not null default 0;
alter table public.experiences
  add column if not exists average_rating numeric(4, 2);
alter table public.experiences
  add column if not exists community_rating_count integer not null default 0;
alter table public.experiences
  add column if not exists community_average_rating numeric(4, 2);
alter table public.experiences
  add column if not exists creator_rating numeric(4, 2);
-- Per-axis community mean, same shape as `rating`, for the hexagon chart.
alter table public.experiences
  add column if not exists community_rating jsonb;
alter table public.experiences
  add column if not exists last_rated_at timestamptz;

alter table public.profiles
  add column if not exists rating_count integer not null default 0;

create index if not exists idx_experiences_community_rating
  on public.experiences (community_average_rating desc nulls last)
  where is_published = true;

create or replace function public.recompute_experience_ratings(p_experience_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_creator uuid;
  v_total_count integer := 0;
  v_total_avg numeric(4, 2);
  v_community_count integer := 0;
  v_community_avg numeric(4, 2);
  v_creator_score numeric(4, 2);
  v_community_axes jsonb;
  v_last_rated timestamptz;
begin
  select user_id into v_creator from public.experiences where id = p_experience_id;
  if v_creator is null then
    return;
  end if;

  select count(*),
         round(avg(overall_score)::numeric, 2),
         count(*) filter (where user_id <> v_creator),
         round(avg(overall_score) filter (where user_id <> v_creator)::numeric, 2),
         max(overall_score) filter (where user_id = v_creator),
         max(coalesce(updated_at, created_at))
    into v_total_count, v_total_avg, v_community_count, v_community_avg,
         v_creator_score, v_last_rated
    from public.ratings
    where experience_id = p_experience_id;

  select jsonb_object_agg(axis, mean)
    into v_community_axes
    from (
      select kv.key as axis, round(avg((kv.value)::numeric), 2) as mean
      from public.ratings r
      cross join lateral jsonb_each_text(r.scores) as kv(key, value)
      where r.experience_id = p_experience_id
        and r.user_id <> v_creator
        and kv.value ~ '^-?[0-9]+(\.[0-9]+)?$'
      group by kv.key
    ) axes;

  update public.experiences
    set rating_count = coalesce(v_total_count, 0),
        average_rating = v_total_avg,
        community_rating_count = coalesce(v_community_count, 0),
        community_average_rating = v_community_avg,
        creator_rating = v_creator_score,
        community_rating = v_community_axes,
        last_rated_at = v_last_rated
    where id = p_experience_id;
end;
$$;

-- Completion is a consequence of rating, never an independent action.
create or replace function public.tg_ratings_sync()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_experience_id uuid := coalesce(new.experience_id, old.experience_id);
  v_user_id uuid := coalesce(new.user_id, old.user_id);
  v_owner uuid;
begin
  if tg_op = 'DELETE' then
    delete from public.experience_completions
      where user_id = v_user_id and experience_id = v_experience_id;
    update public.profiles
      set rating_count = greatest(rating_count - 1, 0), updated_at = now()
      where id = v_user_id;
    perform public.recompute_experience_ratings(v_experience_id);
    return old;
  end if;

  insert into public.experience_completions (user_id, experience_id, note, photo_urls)
    values (v_user_id, v_experience_id, new.review, new.photo_urls)
    on conflict (user_id, experience_id) do update
      set note = excluded.note,
          photo_urls = excluded.photo_urls,
          completed_at = now();

  if tg_op = 'INSERT' then
    update public.profiles
      set rating_count = rating_count + 1, updated_at = now()
      where id = v_user_id;

    select user_id into v_owner from public.experiences where id = v_experience_id;
    if v_owner is not null and v_owner <> v_user_id then
      begin
        perform public.insert_notification(
          v_owner, v_user_id, 'rating'::public.notification_type, v_experience_id
        );
      exception when others then
        -- A notification must never block a rating from being recorded.
        null;
      end;
    end if;
  end if;

  perform public.recompute_experience_ratings(v_experience_id);
  return new;
end;
$$;

create or replace function public.tg_ratings_touch()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists ratings_touch_bu on public.ratings;
create trigger ratings_touch_bu
  before update on public.ratings
  for each row execute function public.tg_ratings_touch();

drop trigger if exists ratings_sync_ai on public.ratings;
create trigger ratings_sync_ai
  after insert on public.ratings
  for each row execute function public.tg_ratings_sync();

drop trigger if exists ratings_sync_au on public.ratings;
create trigger ratings_sync_au
  after update on public.ratings
  for each row execute function public.tg_ratings_sync();

drop trigger if exists ratings_sync_ad on public.ratings;
create trigger ratings_sync_ad
  after delete on public.ratings
  for each row execute function public.tg_ratings_sync();

-- ---------------------------------------------------------------------------
-- A completion without a rating is not a thing anymore
-- ---------------------------------------------------------------------------

create or replace function public.tg_completions_require_rating()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.ratings
    where user_id = new.user_id and experience_id = new.experience_id
  ) then
    raise exception 'TRAV_RATING_REQUIRED: submit a rating to complete this experience'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists completions_require_rating_bi on public.experience_completions;
create trigger completions_require_rating_bi
  before insert on public.experience_completions
  for each row execute function public.tg_completions_require_rating();

-- ---------------------------------------------------------------------------
-- Backfill: migrate the creator radar stored on experiences.rating into ratings
-- ---------------------------------------------------------------------------

insert into public.ratings (user_id, experience_id, scores, overall_score, created_at, updated_at)
select e.user_id,
       e.id,
       case
         when e.rating ? 'scores' then e.rating -> 'scores'
         else e.rating
       end as scores,
       least(greatest(coalesce(agg.mean, 0), 0), 10) as overall_score,
       e.created_at,
       e.created_at
from public.experiences e
cross join lateral (
  select avg((kv.value)::numeric) as mean
  from jsonb_each_text(
    case when e.rating ? 'scores' then e.rating -> 'scores' else e.rating end
  ) as kv(key, value)
  where kv.value ~ '^-?[0-9]+(\.[0-9]+)?$'
    and not (
      e.rating ? 'disabledCategories'
      and (e.rating -> 'disabledCategories') ? kv.key
    )
) agg
where e.rating is not null
  and jsonb_typeof(e.rating) = 'object'
  and agg.mean is not null
on conflict (user_id, experience_id) do nothing;

-- Completions recorded before ratings were mandatory are left as-is: inventing
-- scores would attribute opinions nobody gave. The BEFORE INSERT trigger only
-- constrains completions created from here on.

do $$
declare
  r record;
begin
  for r in select distinct experience_id from public.ratings loop
    perform public.recompute_experience_ratings(r.experience_id);
  end loop;
end;
$$;

update public.profiles p
  set rating_count = coalesce(c.total, 0)
from (select user_id, count(*) as total from public.ratings group by user_id) c
where p.id = c.user_id;

update public.profiles p
  set completion_count = coalesce(c.total, 0)
from (
  select user_id, count(*) as total from public.experience_completions group by user_id
) c
where p.id = c.user_id and p.completion_count <> c.total;
