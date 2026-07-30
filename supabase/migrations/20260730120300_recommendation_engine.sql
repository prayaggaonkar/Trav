-- ---------------------------------------------------------------------------
-- Weighted recommendation engine.
--
-- Replaces chronological feeds with a single ranking function that blends
-- quality, social proof, taste, proximity, freshness and editorial curation,
-- then spreads results across creators, cities and categories so the feed never
-- repeats itself. Everything is derived from base tables — no duplicated state.
-- ---------------------------------------------------------------------------

create or replace function public.distance_km(
  lat1 double precision,
  lon1 double precision,
  lat2 double precision,
  lon2 double precision
)
returns double precision
language sql
immutable
as $$
  select case
    when lat1 is null or lon1 is null or lat2 is null or lon2 is null then null
    else 6371 * 2 * asin(
      least(1, sqrt(
        power(sin(radians(lat2 - lat1) / 2), 2)
        + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lon2 - lon1) / 2), 2)
      ))
    )
  end;
$$;

-- Normalizes an unbounded count into 0..1 with diminishing returns.
create or replace function public.saturate(p_value double precision, p_scale double precision)
returns double precision
language sql
immutable
as $$
  select least(1.0, greatest(0.0, ln(1 + greatest(coalesce(p_value, 0), 0)) / ln(1 + p_scale)));
$$;

create or replace function public.get_personalized_feed(
  p_user_id uuid default null,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_city_id uuid default null,
  p_kind text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  experience_id uuid,
  score double precision,
  reason text
)
language sql
stable
as $$
with params as (
  select
    p_user_id as me,
    p_latitude as lat,
    p_longitude as lng,
    p_city_id as city_id,
    nullif(p_kind, '') as kind,
    -- Proximity matters most when the user has not pinned a city.
    case when p_city_id is null and p_latitude is not null then 0.18 else 0.06 end as w_distance
),
friends as (
  select following_id as id from public.follows where follower_id = p_user_id
),
my_completed as (
  select experience_id from public.experience_completions where user_id = p_user_id
),
my_saved as (
  select experience_id from public.experience_saves where user_id = p_user_id
),
-- Taste inferred from what the user already saved or finished.
my_categories as (
  select lower(e.category) as category, count(*)::double precision as weight
  from public.experiences e
  where e.category is not null
    and (
      e.id in (select experience_id from my_completed)
      or e.id in (select experience_id from my_saved)
    )
  group by lower(e.category)
),
my_vibes as (
  select lower(vibe) as vibe
  from public.profiles p
  cross join lateral unnest(coalesce(p.selected_vibes, '{}')) as v(vibe)
  where p.id = p_user_id
),
-- Users whose completed set overlaps mine are a proxy for taste neighbours.
similar_users as (
  select c.user_id as id, count(*)::double precision as overlap
  from public.experience_completions c
  where c.experience_id in (select experience_id from my_completed)
    and c.user_id is distinct from p_user_id
  group by c.user_id
  order by count(*) desc
  limit 50
),
candidates as (
  select e.id, e.user_id, e.city_id, e.kind, e.title, e.category,
         e.latitude, e.longitude, e.created_at, e.is_featured,
         e.save_count, e.like_count, e.completion_count, e.comment_count,
         e.rating_count, e.average_rating, e.community_rating_count,
         e.community_average_rating
  from public.experiences e
  cross join params pr
  where e.is_published = true
    and (pr.city_id is null or e.city_id = pr.city_id)
    and (pr.kind is null or e.kind::text = pr.kind)
    -- Never re-recommend something the user already finished.
    and (pr.me is null or e.id not in (select experience_id from my_completed))
    -- The user's own itineraries belong on their profile, not their feed.
    and (pr.me is null or e.user_id <> pr.me or e.kind = 'spot')
    and (pr.me is null or not exists (
      select 1 from public.blocks b
      where b.blocker_id = pr.me and b.blocked_id = e.user_id
    ))
),
friend_signal as (
  select x.experience_id, sum(x.weight) as weight
  from (
    select c.experience_id, 3.0 as weight
    from public.experience_completions c
    where c.user_id in (select id from friends)
    union all
    select s.experience_id, 2.0 as weight
    from public.experience_saves s
    where s.user_id in (select id from friends)
  ) x
  group by x.experience_id
),
similar_signal as (
  select c.experience_id, sum(su.overlap) as weight
  from public.experience_completions c
  join similar_users su on su.id = c.user_id
  group by c.experience_id
),
trending_signal as (
  select x.experience_id, sum(x.weight) as weight
  from (
    select experience_id, 1.0 as weight from public.experience_saves
      where created_at > now() - interval '14 days'
    union all
    select experience_id, 2.0 as weight from public.experience_completions
      where completed_at > now() - interval '14 days'
    union all
    select experience_id, 2.0 as weight from public.ratings
      where created_at > now() - interval '14 days'
    union all
    select experience_id, 0.5 as weight from public.comments
      where created_at > now() - interval '14 days'
  ) x
  group by x.experience_id
),
components as (
  select
    c.id,
    c.user_id,
    c.city_id,
    c.category,
    -- Rating quality, damped until enough people have weighed in.
    (coalesce(c.community_average_rating, c.average_rating, 0)::double precision / 10.0)
      * (0.4 + 0.6 * public.saturate(c.rating_count::double precision, 10)) as quality,
    public.saturate(
      c.save_count + 2 * c.completion_count + 0.5 * c.like_count + c.comment_count, 60
    ) as popularity,
    public.saturate(coalesce(fs.weight, 0), 8) as friends,
    public.saturate(coalesce(ss.weight, 0), 12) as similar,
    public.saturate(coalesce(ts.weight, 0), 15) as trending,
    exp(-greatest(extract(epoch from (now() - c.created_at)) / 86400.0, 0) / 45.0) as recency,
    case
      when pr.lat is null or c.latitude is null then 0.35
      else exp(-coalesce(public.distance_km(pr.lat, pr.lng, c.latitude, c.longitude), 50) / 12.0)
    end as proximity,
    least(1.0,
      coalesce((select mc.weight from my_categories mc where mc.category = lower(c.category)), 0) / 3.0
      + case
          when exists (
            select 1 from my_vibes mv
            where lower(coalesce(c.category, '')) like '%' || mv.vibe || '%'
               or lower(c.title) like '%' || mv.vibe || '%'
          ) then 0.5
          else 0.0
        end
    ) as preference,
    case when c.is_featured then 1.0 else 0.0 end as featured,
    case when c.id in (select experience_id from my_saved) then 1.0 else 0.0 end as already_saved,
    pr.w_distance
  from candidates c
  cross join params pr
  left join friend_signal fs on fs.experience_id = c.id
  left join similar_signal ss on ss.experience_id = c.id
  left join trending_signal ts on ts.experience_id = c.id
),
ranked as (
  select
    k.id,
    k.user_id,
    k.city_id,
    k.category,
    k.raw_score,
    k.reason,
    row_number() over (partition by k.user_id order by k.raw_score desc) as creator_rank,
    case
      when k.city_id is null then 1
      else row_number() over (partition by k.city_id order by k.raw_score desc)
    end as city_rank,
    case
      when k.category is null then 1
      else row_number() over (partition by lower(k.category) order by k.raw_score desc)
    end as category_rank
  from (
    select
      cp.*,
      0.20 * cp.quality
      + 0.12 * cp.popularity
      + 0.16 * cp.friends
      + 0.10 * cp.similar
      + 0.12 * cp.preference
      + 0.10 * cp.trending
      + 0.06 * cp.recency
      + cp.w_distance * cp.proximity
      + 0.04 * cp.featured
      -- Already saved: keep it eligible but well behind fresh discoveries.
      - 0.30 * cp.already_saved as raw_score,
      case
        when cp.friends > 0.3 then 'friends'
        when cp.featured > 0 then 'featured'
        when cp.trending > 0.4 then 'trending'
        when cp.similar > 0.3 then 'similar_taste'
        when cp.preference > 0.4 then 'your_taste'
        when cp.quality > 0.6 then 'highly_rated'
        when cp.proximity > 0.7 then 'nearby'
        else 'popular'
      end as reason
    from components cp
  ) k
)
select
  r.id as experience_id,
  -- Diversity: each additional item from the same creator, city or category is
  -- worth progressively less, so the feed keeps moving.
  (r.raw_score
    * power(0.72::double precision, least(r.creator_rank - 1, 6))
    * power(0.94::double precision, least(r.city_rank - 1, 12))
    * power(0.90::double precision, least(r.category_rank - 1, 8))
  )::double precision as score,
  r.reason
from ranked r
order by score desc, r.id
limit greatest(coalesce(p_limit, 20), 1)
offset greatest(coalesce(p_offset, 0), 0);
$$;

grant execute on function public.get_personalized_feed(
  uuid, double precision, double precision, uuid, text, integer, integer
) to authenticated, anon;

grant execute on function public.distance_km(
  double precision, double precision, double precision, double precision
) to authenticated, anon;
grant execute on function public.saturate(double precision, double precision)
  to authenticated, anon;

-- ---------------------------------------------------------------------------
-- Supporting indexes for the ranking joins
-- ---------------------------------------------------------------------------

create index if not exists idx_experience_saves_created
  on public.experience_saves (created_at desc);
create index if not exists idx_experience_completions_completed
  on public.experience_completions (completed_at desc);
create index if not exists idx_ratings_created
  on public.ratings (created_at desc);
create index if not exists idx_comments_created
  on public.comments (created_at desc);
create index if not exists idx_experiences_category
  on public.experiences (category)
  where is_published = true;

-- The existing pgvector path had no index; recommendations fall back to it when
-- an embedding is present.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'vector')
     and not exists (
       select 1 from pg_class where relname = 'idx_experiences_embedding'
     ) then
    execute 'create index idx_experiences_embedding on public.experiences '
      || 'using ivfflat (embedding vector_cosine_ops) with (lists = 100)';
  end if;
exception when others then
  -- ivfflat needs rows to train on; skip silently on an empty table.
  null;
end;
$$;
