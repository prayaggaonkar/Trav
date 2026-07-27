-- Normalized stops table. Experiences.stops (text[]) remains as a denormalized
-- preview for feed cards; this table is the source of truth for coordinates,
-- place IDs, and ordered itinerary detail.

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

create index if not exists idx_stops_experience_order
  on public.stops (experience_id, order_index);

alter table public.stops enable row level security;

drop policy if exists "Stops are publicly readable" on public.stops;
create policy "Stops are publicly readable"
  on public.stops for select using (true);

drop policy if exists "Creators can insert stops" on public.stops;
create policy "Creators can insert stops"
  on public.stops for insert
  with check (
    exists (
      select 1 from public.experiences e
      where e.id = experience_id and e.user_id = auth.uid()
    )
  );

drop policy if exists "Creators can update stops" on public.stops;
create policy "Creators can update stops"
  on public.stops for update
  using (
    exists (
      select 1 from public.experiences e
      where e.id = experience_id and e.user_id = auth.uid()
    )
  );

drop policy if exists "Creators can delete stops" on public.stops;
create policy "Creators can delete stops"
  on public.stops for delete
  using (
    exists (
      select 1 from public.experiences e
      where e.id = experience_id and e.user_id = auth.uid()
    )
  );

grant select on public.stops to anon, authenticated;
grant insert, update, delete on public.stops to authenticated;
