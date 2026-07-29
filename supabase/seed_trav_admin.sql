-- 1. Create Trav Admin user in auth.users if not exists
insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at,
  raw_app_meta_data,
  raw_user_meta_data,
  is_super_admin
)
values (
  '00000000-0000-0000-0000-000000000000',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'admin@trav.app',
  '$2a$10$abcdefghijklmnopqrstuuv',
  now(),
  now(),
  now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Rec by Trav"}',
  false
)
on conflict (id) do nothing;

-- 2. Create Trav Admin profile in public.profiles if not exists
insert into public.profiles (
  id,
  username,
  display_name,
  bio,
  is_verified
)
values (
  '00000000-0000-0000-0000-000000000000',
  'trav',
  'Rec by Trav',
  'Official curated itineraries by Trav.',
  true
)
on conflict (id) do nothing;

-- 3. Insert Rec by Trav experience into public.experiences
insert into public.experiences (
  id,
  user_id,
  title,
  city,
  stops,
  description,
  rating,
  is_published,
  created_at
) values (
  gen_random_uuid(),
  '00000000-0000-0000-0000-000000000000',
  'San Francisco Hidden Gems & Coffee Crawl',
  'San Francisco',
  array['Blue Bottle Coffee', 'City Lights Books', 'Dolores Park', 'Tartine Manufactory'],
  'The ultimate local day loop in SF featuring artisanal coffee, historic bookshops, and sunset park vibes.',
  '{"overallScore": 9.4}'::jsonb,
  true,
  now()
);
