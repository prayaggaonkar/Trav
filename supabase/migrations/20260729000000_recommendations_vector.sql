-- Migration: Native AI Recommendations using pgvector
-- Enable vector extension
create extension if not exists vector;

-- Alter experiences table to add vector embedding column (512 dimensions)
alter table public.experiences add column if not exists embedding vector(512);

-- Create Postgres RPC function for vector similarity matching
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

grant execute on function public.get_recommended_feed(vector(512), int) to authenticated, anon;
