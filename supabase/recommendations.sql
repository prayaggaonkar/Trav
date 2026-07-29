-- Enable vector extension
create extension if not exists vector;

-- Alter experiences table to add 512-dimensional vector embedding column for Apple's NaturalLanguage sentence embedding
alter table public.experiences add column if not exists embedding vector(512);

-- Postgres RPC function get_recommended_feed
create or replace function public.get_recommended_feed(
  user_profile_vector vector(512),
  match_limit int default 15
)
returns setof public.experiences
language sql
stable
as $$
  select *
  from public.experiences
  where is_published = true
  order by embedding <=> user_profile_vector
  limit match_limit;
$$;

-- Grant execution permissions
grant execute on function public.get_recommended_feed(vector(512), int) to authenticated, anon;
