-- Experiences table backing SupabaseExperienceRepository.
-- Aligned with user's table: id, user_id, title, description, city, stops, created_at.

CREATE TABLE IF NOT EXISTS public.experiences (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  title text NOT NULL,
  description text NOT NULL,
  city text NOT NULL,
  stops text[] NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Index for searching/filtering by city
CREATE INDEX IF NOT EXISTS idx_experiences_city_created ON public.experiences (city, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_experiences_user ON public.experiences (user_id);

-- Enable Row Level Security (RLS)
ALTER TABLE public.experiences ENABLE ROW LEVEL SECURITY;

-- Experiences policies
CREATE POLICY "Experiences are publicly readable" ON public.experiences FOR SELECT USING (true);
CREATE POLICY "Users can insert their own experiences" ON public.experiences FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own experiences" ON public.experiences FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own experiences" ON public.experiences FOR DELETE USING (auth.uid() = user_id);

-- Grant privileges
GRANT SELECT ON public.experiences TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.experiences TO authenticated;
