-- Migration: Create public.experience_completions table and triggers for watchlist/completion tracking.

create table if not exists public.experience_completions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  experience_id uuid not null references public.experiences (id) on delete cascade,
  completed_at timestamptz not null default now(),
  note text,
  photo_urls text[] not null default '{}',
  unique (user_id, experience_id)
);

create index if not exists idx_experience_completions_user
  on public.experience_completions (user_id, completed_at desc);
create index if not exists idx_experience_completions_experience
  on public.experience_completions (experience_id);

alter table public.experience_completions enable row level security;

drop policy if exists "Completions are publicly readable" on public.experience_completions;
create policy "Completions are publicly readable"
  on public.experience_completions for select using (true);

drop policy if exists "Users can complete experiences" on public.experience_completions;
create policy "Users can complete experiences"
  on public.experience_completions for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their completions" on public.experience_completions;
create policy "Users can update their completions"
  on public.experience_completions for update
  using (auth.uid() = user_id);

drop policy if exists "Users can delete their completions" on public.experience_completions;
create policy "Users can delete their completions"
  on public.experience_completions for delete
  using (auth.uid() = user_id);

grant select on public.experience_completions to anon;
grant select, insert, update, delete on public.experience_completions to authenticated;

create or replace function public.tg_experience_completions_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.experiences
      set completion_count = completion_count + 1
      where id = new.experience_id;
    update public.profiles
      set completion_count = completion_count + 1, updated_at = now()
      where id = new.user_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.experiences
      set completion_count = greatest(completion_count - 1, 0)
      where id = old.experience_id;
    update public.profiles
      set completion_count = greatest(completion_count - 1, 0), updated_at = now()
      where id = old.user_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists experience_completions_counts_ai on public.experience_completions;
create trigger experience_completions_counts_ai
  after insert on public.experience_completions
  for each row execute function public.tg_experience_completions_counts();

drop trigger if exists experience_completions_counts_ad on public.experience_completions;
create trigger experience_completions_counts_ad
  after delete on public.experience_completions
  for each row execute function public.tg_experience_completions_counts();
