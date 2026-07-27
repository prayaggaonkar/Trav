-- Storage buckets for experience media and completion photos.
-- Path convention puts the uploader's user id in the first folder so
-- owner-scoped RLS works with the anon key + user JWT:
--   experiences:  {user_id}/{experience_id}/photo_{index}.jpg
--   completions:  {user_id}/{completion_id}/photo_{index}.jpg

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('experiences', 'experiences', true, 10485760,
   array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']),
  ('completions', 'completions', true, 10485760,
   array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Experience media is publicly accessible" on storage.objects;
drop policy if exists "Users can upload experience media" on storage.objects;
drop policy if exists "Users can update their experience media" on storage.objects;
drop policy if exists "Users can delete their experience media" on storage.objects;
drop policy if exists "Completion photos are publicly accessible" on storage.objects;
drop policy if exists "Users can upload completion photos" on storage.objects;
drop policy if exists "Users can delete their completion photos" on storage.objects;

create policy "Experience media is publicly accessible"
on storage.objects for select
using (bucket_id = 'experiences');

create policy "Users can upload experience media"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'experiences'
  and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
);

create policy "Users can update their experience media"
on storage.objects for update
to authenticated
using (
  bucket_id = 'experiences'
  and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
)
with check (
  bucket_id = 'experiences'
  and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
);

create policy "Users can delete their experience media"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'experiences'
  and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
);

create policy "Completion photos are publicly accessible"
on storage.objects for select
using (bucket_id = 'completions');

create policy "Users can upload completion photos"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'completions'
  and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
);

create policy "Users can delete their completion photos"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'completions'
  and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
);
