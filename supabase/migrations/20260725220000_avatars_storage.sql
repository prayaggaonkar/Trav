-- Public avatars bucket + owner-scoped write policies.
-- Path convention: `{user_id}/avatar.jpg` (matches SupabaseProfileRepository.uploadAvatar).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  true,
  5242880, -- 5 MB
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Idempotent policy setup
drop policy if exists "Avatar images are publicly accessible" on storage.objects;
drop policy if exists "Users can upload their own avatar" on storage.objects;
drop policy if exists "Users can update their own avatar" on storage.objects;
drop policy if exists "Users can delete their own avatar" on storage.objects;

create policy "Avatar images are publicly accessible"
on storage.objects
for select
using (bucket_id = 'avatars');

create policy "Users can upload their own avatar"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
);

create policy "Users can update their own avatar"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatars'
  and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
)
with check (
  bucket_id = 'avatars'
  and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
);

create policy "Users can delete their own avatar"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'avatars'
  and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
);
