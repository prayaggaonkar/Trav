-- Allow authenticated users to insert new cities when publishing experiences
-- for locations that do not yet exist in the public.cities catalog.

drop policy if exists "Authenticated users can insert cities" on public.cities;
create policy "Authenticated users can insert cities"
  on public.cities for insert
  with check (auth.role() = 'authenticated');

drop policy if exists "Authenticated users can update cities" on public.cities;
create policy "Authenticated users can update cities"
  on public.cities for update
  using (auth.role() = 'authenticated');

grant select on public.cities to anon;
grant select, insert, update on public.cities to authenticated;
