// Supabase Edge Function: fan out APNs pushes when a notification row is inserted.
// Wire via Database Webhook on `public.notifications` INSERT → this function.
//
// Secrets (set via `supabase secrets set`):
//   APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_PRIVATE_KEY (PKCS8 PEM),
//   APNS_PRODUCTION ("true" for App Store / TestFlight)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const encoder = new TextEncoder();

async function importAPNsKey(pem: string): Promise<CryptoKey> {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    raw,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

function b64url(bytes: ArrayBuffer | Uint8Array): string {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let str = "";
  for (const b of arr) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function apnsJWT(
  key: CryptoKey,
  keyId: string,
  teamId: string,
): Promise<string> {
  const header = b64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: keyId })));
  const now = Math.floor(Date.now() / 1000);
  const payload = b64url(encoder.encode(JSON.stringify({ iss: teamId, iat: now })));
  const data = encoder.encode(`${header}.${payload}`);
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, data);
  return `${header}.${payload}.${b64url(sig)}`;
}

Deno.serve(async (req) => {
  try {
    const body = await req.json();
    const record = body.record ?? body;
    const userId: string | undefined = record.user_id;
    const type: string = record.type ?? "notification";
    const referenceId: string | undefined = record.reference_id;
    const actorId: string | undefined = record.actor_id;

    if (!userId) {
      return new Response(JSON.stringify({ ok: false, error: "missing user_id" }), {
        status: 400,
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: tokens, error } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("user_id", userId);

    if (error) throw error;
    if (!tokens?.length) {
      return new Response(JSON.stringify({ ok: true, sent: 0 }), { status: 200 });
    }

    const keyId = Deno.env.get("APNS_KEY_ID")!;
    const teamId = Deno.env.get("APNS_TEAM_ID")!;
    const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "com.trav.app";
    const pem = Deno.env.get("APNS_PRIVATE_KEY")!;
    const production = Deno.env.get("APNS_PRODUCTION") === "true";
    const host = production
      ? "https://api.push.apple.com"
      : "https://api.sandbox.push.apple.com";

    const key = await importAPNsKey(pem);
    const jwt = await apnsJWT(key, keyId, teamId);

    let title = "Trav";
    let bodyText = "You have a new notification";
    let deepLink = "trav://notifications";

    switch (type) {
      case "follow":
        title = "New follower";
        bodyText = "Someone started following you";
        if (actorId) deepLink = `trav://profile/${actorId}`;
        break;
      case "save":
        title = "Someone saved your experience";
        bodyText = "Your experience was bookmarked";
        if (referenceId) deepLink = `trav://experience/${referenceId}`;
        break;
      case "like":
        title = "New like";
        bodyText = "Someone liked your experience";
        if (referenceId) deepLink = `trav://experience/${referenceId}`;
        break;
      case "comment":
        title = "New comment";
        bodyText = "Someone commented on your experience";
        if (referenceId) deepLink = `trav://experience/${referenceId}`;
        break;
      case "new_experience":
        title = "New experience";
        bodyText = "Someone you follow posted an experience";
        if (referenceId) deepLink = `trav://experience/${referenceId}`;
        break;
      case "watchlist":
        title = "Added to a watchlist";
        bodyText = "Someone watchlisted an experience";
        if (referenceId) deepLink = `trav://experience/${referenceId}`;
        break;
    }

    let sent = 0;
    for (const row of tokens) {
      const res = await fetch(`${host}/3/device/${row.token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": bundleId,
          "apns-push-type": "alert",
          "apns-priority": "10",
          "content-type": "application/json",
        },
        body: JSON.stringify({
          aps: {
            alert: { title, body: bodyText },
            sound: "default",
            badge: 1,
          },
          deep_link: deepLink,
        }),
      });
      if (res.ok) sent += 1;
    }

    return new Response(JSON.stringify({ ok: true, sent }), { status: 200 });
  } catch (err) {
    return new Response(JSON.stringify({ ok: false, error: String(err) }), {
      status: 500,
    });
  }
});
