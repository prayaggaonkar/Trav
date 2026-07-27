# push-on-notification

Fans out APNs pushes when a row is inserted into `public.notifications`.

## Deploy

```bash
supabase functions deploy push-on-notification
supabase secrets set \
  APNS_KEY_ID=... \
  APNS_TEAM_ID=... \
  APNS_BUNDLE_ID=com.trav.app \
  APNS_PRIVATE_KEY="$(cat AuthKey_XXXX.p8)" \
  APNS_PRODUCTION=false
```

## Wire the webhook

Supabase Dashboard → Database → Webhooks → create on `notifications` INSERT →
HTTP POST to the Edge Function URL with the service role.

## Local testing

Use the APNs sandbox (`APNS_PRODUCTION=false`) with a development build that has
registered a device token via Settings → Notifications.
