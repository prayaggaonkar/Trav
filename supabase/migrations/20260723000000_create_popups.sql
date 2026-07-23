-- Migration to create the popups table for local event/popup aggregation
CREATE TABLE IF NOT EXISTS public.popups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_name text NOT NULL,
  address text NOT NULL DEFAULT 'Berkeley, CA',
  start_time timestamptz,
  end_time timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.popups ENABLE ROW LEVEL SECURITY;

-- Set up RLS Policies
CREATE POLICY "Popups are publicly readable" ON public.popups FOR SELECT USING (true);
CREATE POLICY "Users can insert popups" ON public.popups FOR INSERT WITH CHECK (true);

-- Grant access rights to client roles
GRANT SELECT, INSERT ON public.popups TO anon, authenticated;
