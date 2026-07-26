-- Persist creator radar ratings on experiences (scores dict as jsonb).
-- App already reads/writes `rating`; this aligns the committed schema.

ALTER TABLE public.experiences
  ADD COLUMN IF NOT EXISTS rating jsonb;

COMMENT ON COLUMN public.experiences.rating IS
  'Creator radar scores as JSON object, e.g. {"Cost": 5.5, "Food": 9.0}.';

CREATE INDEX IF NOT EXISTS idx_experiences_rating_not_null
  ON public.experiences (created_at DESC)
  WHERE rating IS NOT NULL;
