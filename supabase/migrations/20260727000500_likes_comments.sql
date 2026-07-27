-- Likes and comments: the core social engagement loop.
-- Counter columns live on experiences; counts maintained by triggers.
-- Notifications fan out to the experience owner via insert_notification.

alter table public.experiences
  add column if not exists like_count integer not null default 0;
alter table public.experiences
  add column if not exists comment_count integer not null default 0;

-- ---------------------------------------------------------------------------
-- experience_likes
-- ---------------------------------------------------------------------------
create table if not exists public.experience_likes (
  user_id uuid not null references public.profiles (id) on delete cascade,
  experience_id uuid not null references public.experiences (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, experience_id)
);

create index if not exists idx_experience_likes_experience
  on public.experience_likes (experience_id);
create index if not exists idx_experience_likes_user
  on public.experience_likes (user_id, created_at desc);

alter table public.experience_likes enable row level security;

drop policy if exists "Likes are publicly readable" on public.experience_likes;
create policy "Likes are publicly readable"
  on public.experience_likes for select using (true);

drop policy if exists "Users can like experiences" on public.experience_likes;
create policy "Users can like experiences"
  on public.experience_likes for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can unlike experiences" on public.experience_likes;
create policy "Users can unlike experiences"
  on public.experience_likes for delete
  using (auth.uid() = user_id);

grant select on public.experience_likes to anon;
grant select, insert, delete on public.experience_likes to authenticated;

create or replace function public.tg_experience_likes_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid;
begin
  if tg_op = 'INSERT' then
    update public.experiences set like_count = like_count + 1
      where id = new.experience_id
      returning user_id into owner_id;

    perform public.insert_notification(
      owner_id,
      new.user_id,
      'like'::public.notification_type,
      new.experience_id
    );
    return new;
  elsif tg_op = 'DELETE' then
    update public.experiences set like_count = greatest(like_count - 1, 0)
      where id = old.experience_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists experience_likes_counts_ai on public.experience_likes;
create trigger experience_likes_counts_ai
  after insert on public.experience_likes
  for each row execute function public.tg_experience_likes_counts();

drop trigger if exists experience_likes_counts_ad on public.experience_likes;
create trigger experience_likes_counts_ad
  after delete on public.experience_likes
  for each row execute function public.tg_experience_likes_counts();

-- ---------------------------------------------------------------------------
-- comments
-- ---------------------------------------------------------------------------
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  experience_id uuid not null references public.experiences (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  parent_id uuid references public.comments (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_comments_experience_created
  on public.comments (experience_id, created_at desc);
create index if not exists idx_comments_author
  on public.comments (author_id);

alter table public.comments enable row level security;

drop policy if exists "Comments are publicly readable" on public.comments;
create policy "Comments are publicly readable"
  on public.comments for select using (true);

drop policy if exists "Users can comment" on public.comments;
create policy "Users can comment"
  on public.comments for insert
  with check (auth.uid() = author_id);

drop policy if exists "Users can edit their comments" on public.comments;
create policy "Users can edit their comments"
  on public.comments for update
  using (auth.uid() = author_id);

drop policy if exists "Users can delete their comments" on public.comments;
create policy "Users can delete their comments"
  on public.comments for delete
  using (auth.uid() = author_id);

grant select on public.comments to anon;
grant select, insert, update, delete on public.comments to authenticated;

create or replace function public.tg_comments_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid;
begin
  if tg_op = 'INSERT' then
    update public.experiences set comment_count = comment_count + 1
      where id = new.experience_id
      returning user_id into owner_id;

    perform public.insert_notification(
      owner_id,
      new.author_id,
      'comment'::public.notification_type,
      new.experience_id
    );
    return new;
  elsif tg_op = 'DELETE' then
    update public.experiences set comment_count = greatest(comment_count - 1, 0)
      where id = old.experience_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists comments_counts_ai on public.comments;
create trigger comments_counts_ai
  after insert on public.comments
  for each row execute function public.tg_comments_counts();

drop trigger if exists comments_counts_ad on public.comments;
create trigger comments_counts_ad
  after delete on public.comments
  for each row execute function public.tg_comments_counts();
