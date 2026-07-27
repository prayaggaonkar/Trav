# Secrets Rotation Checklist

A Supabase **service_role** JWT was previously committed under the name `SUPABASE_ANON_KEY`. Treat that key as compromised.

## Immediate steps (dashboard)

1. Open the Supabase project → **Settings → API**.
2. **Rotate the service_role key** (and prefer rotating the anon key too if it was ever mixed up).
3. Copy the new **anon (public)** key into local `Trav/Resources/Secrets.xcconfig` (gitignored).
4. Put the new **service_role** key only in `backend_data_pipeline/.env` (gitignored) — never in the iOS app.
5. Redeploy any Edge Functions that use the service role (`push-on-notification`).

## Repo hygiene (already done in tree)

- `.gitignore` ignores `**/Secrets.xcconfig`, `*.env`, and `debug.log`.
- `Secrets.example.xcconfig` and `backend_data_pipeline/.env.example` document the correct keys.
- Local secret files are untracked.

## History scrub (requires explicit approval)

If the compromised key remains in git history on a remote:

```bash
# Example with git-filter-repo (destructive — coordinate with collaborators)
git filter-repo --path Trav/Resources/Secrets.xcconfig --path backend_data_pipeline/.env --invert-paths
git push --force --all
```

Only force-push after every collaborator is ready to re-clone or reset.
