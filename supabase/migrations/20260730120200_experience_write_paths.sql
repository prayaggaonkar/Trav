-- ---------------------------------------------------------------------------
-- Canonical write paths.
--
--   sync_spot()         — idempotent upsert of a provider place into a Spot.
--                         Users call this instead of inserting experiences, so
--                         a spot can never be duplicated or user-authored.
--   publish_itinerary() — atomic itinerary + stops insert with all the
--                         invariants enforced server-side (>= 2 distinct stops,
--                         no duplicate itineraries).
--   submit_rating()     — upsert a rating, which is what marks an experience
--                         complete.
--
-- Errors are raised with a TRAV_* prefix so the client can map them to copy.
-- ---------------------------------------------------------------------------

-- Owner used for provider-sourced spots. Falls back to the caller when the
-- Trav admin profile has not been seeded.
create or replace function public.trav_content_owner()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  select id into v_owner from public.profiles
    where id = '00000000-0000-0000-0000-000000000000'::uuid;
  if v_owner is null then
    select id into v_owner from public.profiles where lower(username) = 'trav' limit 1;
  end if;
  return coalesce(v_owner, auth.uid());
end;
$$;

-- ---------------------------------------------------------------------------
-- Spots
-- ---------------------------------------------------------------------------

create or replace function public.sync_spot(
  p_place_id text default null,
  p_name text default null,
  p_description text default '',
  p_city text default '',
  p_city_id uuid default null,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_image_urls text[] default '{}',
  p_category text default null,
  p_emoji text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text;
  v_id uuid;
  v_owner uuid;
  v_name text := btrim(coalesce(p_name, ''));
  v_images jsonb;
begin
  v_key := public.spot_identity_key(p_place_id, v_name, p_latitude, p_longitude);
  if v_key is null then
    raise exception 'TRAV_INVALID_SPOT: a spot needs a provider id or a name'
      using errcode = 'check_violation';
  end if;

  select id into v_id from public.experiences
    where kind = 'spot' and spot_key = v_key;

  v_images := case
    when coalesce(array_length(p_image_urls, 1), 0) > 0 then to_jsonb(p_image_urls)
    else null
  end;

  if v_id is not null then
    -- Refresh provider-owned fields; never touch engagement or ratings.
    update public.experiences
      set title = coalesce(nullif(v_name, ''), title),
          description = case
            when coalesce(btrim(p_description), '') <> '' then p_description
            else description
          end,
          city = coalesce(nullif(btrim(coalesce(p_city, '')), ''), city),
          city_id = coalesce(p_city_id, city_id),
          latitude = coalesce(p_latitude, latitude),
          longitude = coalesce(p_longitude, longitude),
          category = coalesce(p_category, category),
          image = coalesce(v_images, image),
          source_place_id = coalesce(nullif(btrim(coalesce(p_place_id, '')), ''), source_place_id),
          is_published = true
      where id = v_id;
    return v_id;
  end if;

  v_owner := public.trav_content_owner();
  if v_owner is null then
    raise exception 'TRAV_NO_OWNER: no profile available to own synced spots'
      using errcode = 'check_violation';
  end if;

  -- Deterministic id so the same place always resolves to the same spot,
  -- even across devices that derive the id client-side.
  v_id := public.stable_uuid(coalesce(nullif(btrim(coalesce(p_place_id, '')), ''), v_key));

  insert into public.experiences (
    id, user_id, kind, spot_key, title, description, city, city_id,
    stops, image, latitude, longitude, category, source_place_id, is_published
  )
  values (
    v_id, v_owner, 'spot', v_key,
    coalesce(nullif(v_name, ''), 'Spot'),
    coalesce(p_description, ''),
    coalesce(nullif(btrim(coalesce(p_city, '')), ''), ''),
    p_city_id,
    array[
      jsonb_build_object(
        'id', v_id,
        'name', coalesce(nullif(v_name, ''), 'Spot'),
        'emoji', p_emoji,
        'description', coalesce(p_description, ''),
        'latitude', coalesce(p_latitude, 0),
        'longitude', coalesce(p_longitude, 0),
        'place_id', p_place_id,
        'orderIndex', 0,
        'creator_notes', '',
        'duration_minutes', 60
      )::text
    ],
    v_images,
    p_latitude, p_longitude, p_category,
    nullif(btrim(coalesce(p_place_id, '')), ''),
    true
  )
  on conflict (id) do update
    set spot_key = coalesce(experiences.spot_key, excluded.spot_key),
        kind = 'spot'
  returning id into v_id;

  insert into public.stops (
    experience_id, order_index, name, description, creator_notes,
    latitude, longitude, place_id, duration_minutes, emoji, spot_id
  )
  values (
    v_id, 0, coalesce(nullif(v_name, ''), 'Spot'), coalesce(p_description, ''), '',
    p_latitude, p_longitude, nullif(btrim(coalesce(p_place_id, '')), ''), 60, p_emoji, v_id
  )
  on conflict (experience_id, order_index) do nothing;

  return v_id;
end;
$$;

grant execute on function public.sync_spot(
  text, text, text, text, uuid, double precision, double precision, text[], text, text
) to authenticated, anon;

-- ---------------------------------------------------------------------------
-- Itineraries
-- ---------------------------------------------------------------------------

-- payload: {
--   title, description, city, city_id, image_urls: [text],
--   stops: [{ name, description, creator_notes, latitude, longitude,
--             place_id, recommended_time, duration_minutes, emoji }]
-- }
create or replace function public.publish_itinerary(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid := gen_random_uuid();
  v_stops jsonb := coalesce(p_payload -> 'stops', '[]'::jsonb);
  v_keys text[] := '{}';
  v_stop_payloads text[] := '{}';
  v_count integer;
  v_signature text;
  v_existing uuid;
  v_images text[] := coalesce(
    (select array_agg(value) from jsonb_array_elements_text(p_payload -> 'image_urls')),
    '{}'
  );
  v_stop jsonb;
  v_key text;
  v_spot_id uuid;
  v_index integer := 0;
  v_name text;
begin
  if v_user is null then
    raise exception 'TRAV_UNAUTHORIZED: sign in to publish an itinerary'
      using errcode = 'insufficient_privilege';
  end if;

  if jsonb_typeof(v_stops) <> 'array' then
    raise exception 'TRAV_MIN_STOPS: an itinerary needs at least 2 spots'
      using errcode = 'check_violation';
  end if;

  -- Collect identity keys, rejecting repeats up front so the user gets a clear
  -- error instead of a constraint violation.
  for v_stop in select value from jsonb_array_elements(v_stops) loop
    v_name := btrim(coalesce(v_stop ->> 'name', ''));
    if v_name = '' then
      raise exception 'TRAV_INVALID_STOP: every stop needs a name'
        using errcode = 'check_violation';
    end if;

    v_key := public.spot_identity_key(
      v_stop ->> 'place_id',
      v_name,
      (v_stop ->> 'latitude')::double precision,
      (v_stop ->> 'longitude')::double precision
    );

    if v_key = any(v_keys) then
      raise exception 'TRAV_DUPLICATE_STOP: % appears more than once', v_name
        using errcode = 'check_violation';
    end if;

    v_keys := array_append(v_keys, v_key);
  end loop;

  v_count := coalesce(array_length(v_keys, 1), 0);
  if v_count < 2 then
    raise exception 'TRAV_MIN_STOPS: an itinerary needs at least 2 spots'
      using errcode = 'check_violation';
  end if;

  v_signature := public.itinerary_route_signature(v_keys);

  select id into v_existing from public.experiences
    where kind = 'itinerary' and route_signature = v_signature limit 1;

  if v_existing is null then
    -- Same spots in a different order, or an overwhelming overlap, still counts
    -- as the same journey.
    select e.id into v_existing
    from public.experiences e
    join public.stops s on s.experience_id = e.id
    where e.kind = 'itinerary' and e.is_published = true
    group by e.id
    having count(*) = v_count
       and count(*) filter (where s.stop_key = any(v_keys))
             >= greatest(2, ceil(v_count * 0.8))
    limit 1;
  end if;

  if v_existing is not null then
    raise exception 'TRAV_DUPLICATE_ITINERARY: % already covers these spots', v_existing
      using errcode = 'unique_violation';
  end if;

  insert into public.experiences (
    id, user_id, kind, title, description, city, city_id,
    stops, image, route_signature, is_published
  )
  values (
    v_id, v_user, 'itinerary',
    coalesce(nullif(btrim(coalesce(p_payload ->> 'title', '')), ''), 'Untitled itinerary'),
    coalesce(p_payload ->> 'description', ''),
    coalesce(p_payload ->> 'city', ''),
    nullif(p_payload ->> 'city_id', '')::uuid,
    '{}',
    case when array_length(v_images, 1) > 0 then to_jsonb(v_images) else null end,
    v_signature,
    true
  );

  for v_stop in select value from jsonb_array_elements(v_stops) loop
    v_name := btrim(v_stop ->> 'name');

    -- Every stop resolves to a canonical spot, so itineraries are genuinely
    -- composed of Spots and spot engagement stays unified.
    v_spot_id := public.sync_spot(
      p_place_id => v_stop ->> 'place_id',
      p_name => v_name,
      p_description => coalesce(v_stop ->> 'description', ''),
      p_city => coalesce(p_payload ->> 'city', ''),
      p_city_id => nullif(p_payload ->> 'city_id', '')::uuid,
      p_latitude => (v_stop ->> 'latitude')::double precision,
      p_longitude => (v_stop ->> 'longitude')::double precision,
      p_image_urls => '{}',
      p_category => v_stop ->> 'category',
      p_emoji => v_stop ->> 'emoji'
    );

    insert into public.stops (
      experience_id, order_index, name, description, creator_notes,
      latitude, longitude, place_id, recommended_time, duration_minutes, emoji, spot_id
    )
    values (
      v_id, v_index, v_name,
      coalesce(v_stop ->> 'description', ''),
      coalesce(v_stop ->> 'creator_notes', ''),
      (v_stop ->> 'latitude')::double precision,
      (v_stop ->> 'longitude')::double precision,
      nullif(btrim(coalesce(v_stop ->> 'place_id', '')), ''),
      v_stop ->> 'recommended_time',
      coalesce((v_stop ->> 'duration_minutes')::integer, 30),
      v_stop ->> 'emoji',
      v_spot_id
    );

    v_stop_payloads := array_append(v_stop_payloads, jsonb_build_object(
      'id', v_spot_id,
      'name', v_name,
      'emoji', v_stop ->> 'emoji',
      'description', coalesce(v_stop ->> 'description', ''),
      'latitude', coalesce((v_stop ->> 'latitude')::double precision, 0),
      'longitude', coalesce((v_stop ->> 'longitude')::double precision, 0),
      'place_id', v_stop ->> 'place_id',
      'orderIndex', v_index,
      'creator_notes', coalesce(v_stop ->> 'creator_notes', ''),
      'duration_minutes', coalesce((v_stop ->> 'duration_minutes')::integer, 30)
    )::text);

    v_index := v_index + 1;
  end loop;

  -- Denormalized preview used by feed cards.
  update public.experiences
    set stops = v_stop_payloads,
        route_signature = v_signature,
        is_published = true
    where id = v_id;

  perform public.recompute_experience_geometry(v_id);

  return v_id;
end;
$$;

grant execute on function public.publish_itinerary(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Ratings
-- ---------------------------------------------------------------------------

create or replace function public.submit_rating(
  p_experience_id uuid,
  p_scores jsonb,
  p_disabled_categories text[] default '{}',
  p_overall_score numeric default null,
  p_review text default null,
  p_photo_urls text[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_overall numeric;
  v_rating_id uuid;
  v_photos text[] := coalesce(p_photo_urls, '{}');
begin
  if v_user is null then
    raise exception 'TRAV_UNAUTHORIZED: sign in to rate an experience'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from public.experiences where id = p_experience_id) then
    raise exception 'TRAV_NOT_FOUND: that experience no longer exists'
      using errcode = 'no_data_found';
  end if;

  if p_scores is null or jsonb_typeof(p_scores) <> 'object' or p_scores = '{}'::jsonb then
    raise exception 'TRAV_RATING_REQUIRED: a rating is required to complete an experience'
      using errcode = 'check_violation';
  end if;

  if coalesce(array_length(v_photos, 1), 0) > 3 then
    raise exception 'TRAV_PHOTO_LIMIT: up to 3 photos per rating'
      using errcode = 'check_violation';
  end if;

  -- Mean of the enabled axes, matching RadarRating.overallScore on the client.
  v_overall := coalesce(
    p_overall_score,
    (
      select avg((kv.value)::numeric)
      from jsonb_each_text(p_scores) as kv(key, value)
      where kv.value ~ '^-?[0-9]+(\.[0-9]+)?$'
        and not (kv.key = any(coalesce(p_disabled_categories, '{}')))
    ),
    0
  );
  v_overall := least(greatest(v_overall, 0), 10);

  insert into public.ratings (
    user_id, experience_id, scores, disabled_categories,
    overall_score, review, photo_urls
  )
  values (
    v_user, p_experience_id, p_scores, coalesce(p_disabled_categories, '{}'),
    v_overall, nullif(btrim(coalesce(p_review, '')), ''), v_photos
  )
  on conflict (user_id, experience_id) do update
    set scores = excluded.scores,
        disabled_categories = excluded.disabled_categories,
        overall_score = excluded.overall_score,
        review = excluded.review,
        photo_urls = excluded.photo_urls,
        updated_at = now()
  returning id into v_rating_id;

  delete from public.photos where rating_id = v_rating_id;
  insert into public.photos (owner_id, rating_id, url, order_index)
  select v_user, v_rating_id, url, (ordinality - 1)::integer
  from unnest(v_photos) with ordinality as t(url, ordinality);

  return v_rating_id;
end;
$$;

grant execute on function public.submit_rating(uuid, jsonb, text[], numeric, text, text[])
  to authenticated;

create or replace function public.delete_rating(p_experience_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'TRAV_UNAUTHORIZED' using errcode = 'insufficient_privilege';
  end if;
  delete from public.ratings
    where user_id = auth.uid() and experience_id = p_experience_id;
end;
$$;

grant execute on function public.delete_rating(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Completion notifications now describe completing, not watchlisting
-- ---------------------------------------------------------------------------

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
         where t.typname = 'notification_type' and e.enumlabel = 'completion'
       ) then
      insert into public.notifications (user_id, actor_id, type, reference_id)
      select f.follower_id, new.user_id, 'completion'::public.notification_type, new.experience_id
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
