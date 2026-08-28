# `whatsapp-test` — WhatsApp Cloud API proof-of-concept

Phase 3A only. Proves the Supabase Edge Functions backend can send a message through Meta's official WhatsApp Cloud API. Does **not** touch Split Bill's `wa.me` reminder flow (`lib/features/bill_split/`, `lib/domain/logic/phone_number.dart`, `lib/domain/logic/whatsapp_reminder_link.dart`) — that remains the only WhatsApp integration point end users see today. Wiring this into it is explicitly out-of-scope future work (Phase 3B), not covered here.

Canonical request/response/error-code reference: [overview.md](overview.md).

## 1. One-time Meta dashboard setup

1. Create (or reuse) a Meta developer app at [developers.facebook.com](https://developers.facebook.com) → My Apps.
2. Add the "WhatsApp" product to the app. This auto-provisions a test WhatsApp Business Account (WABA) and one test phone number — no business verification needed for testing.
3. Under **WhatsApp → API Setup** you'll see:
   - **Phone number ID** — the value for `WHATSAPP_PHONE_NUMBER_ID` (numeric, not the phone number itself).
   - A **temporary access token** (24h) — good enough for this PoC. For something longer-lived, create a System User under Business Settings → Users → System Users, generate a token for it scoped to `whatsapp_business_messaging`, and assign it to your app/WABA.
4. On the same API Setup page, under "To": add the real WhatsApp number you want to receive the test message, in international format. Meta enforces this allowlist server-side for test numbers — sends to any other number are rejected (this is what the `invalid_recipient` error code reports).
5. That allowed number becomes `WHATSAPP_TEST_RECIPIENT` — digits only, country code, no `+` (e.g. `60123456789`).

## 2. Configure secrets

Local dev — add to `supabase/functions/.env` (copied from `.env.example`, never committed):

```
WHATSAPP_ACCESS_TOKEN=...
WHATSAPP_PHONE_NUMBER_ID=...
WHATSAPP_TEST_RECIPIENT=...
```

Deployed environments:

```
supabase secrets set WHATSAPP_ACCESS_TOKEN=... WHATSAPP_PHONE_NUMBER_ID=... WHATSAPP_TEST_RECIPIENT=...
```

## 3. Deploy

```
supabase functions deploy whatsapp-test
```

No `[functions.whatsapp-test]` override is needed in `supabase/config.toml` — default `verify_jwt = true` already applies, same as `ocr-proxy`/`enrich-transaction`.

## 4. Invoke

Against a deployed project:

```
curl -X POST "https://<project-ref>.supabase.co/functions/v1/whatsapp-test" \
  -H "Authorization: Bearer <a real logged-in user's Supabase access token>"
```

Or locally against `supabase start`:

```
curl -X POST "http://127.0.0.1:54321/functions/v1/whatsapp-test" \
  -H "Authorization: Bearer <local test user's access token>"
```

Expected success response:

```json
{ "ok": true, "message_id": "wamid.HBgLNjAxMjM0NTY3ODkVAgARGBI5QTI4RUExRjZBMTIzNDU2AA==" }
```

Then check the phone added as `WHATSAPP_TEST_RECIPIENT` for a WhatsApp message from Meta's test number containing the `hello_world` template body ("Hello World").

## 5. Common failure responses

| `error` | Meaning | Fix |
|---|---|---|
| `unauthorized` | Missing/invalid Supabase bearer token | Pass a real logged-in user's access token |
| `server_misconfigured` | One of the three `WHATSAPP_*` secrets is unset | Re-check step 2 |
| `invalid_or_expired_token` | Meta access token expired (24h temp tokens) or revoked | Generate a new token (step 1.3) |
| `invalid_recipient` | `WHATSAPP_TEST_RECIPIENT` isn't on the app's allowed test-recipient list | Add it under API Setup → "To" (step 1.4) |
| `invalid_phone_number_id` | `WHATSAPP_PHONE_NUMBER_ID` is wrong or inaccessible to this token | Re-copy from API Setup |
| `meta_api_rejected` | Some other Graph API rejection | Check server logs (`console.error` line) for Meta's actual code/type/fbtrace_id |
| `unexpected_upstream_response` | Meta returned a 200 with an unexpected shape, or a non-JSON body | Check server logs; likely a Graph API version mismatch |
| `upstream_timeout` / `upstream_unreachable` | Network issue reaching `graph.facebook.com` | Retry; check outbound network from the Edge Runtime |
| `invalid_json` | Request body was non-empty but not valid JSON | Send no body, or a valid JSON body |
| `method_not_allowed` | Anything other than `POST`/`OPTIONS` | Use `POST` |

## Out of scope (Phase 3B, not this PoC)

- Free-form (non-template) messages, or a custom business-initiated template.
- Any wiring into Split Bill reminders, or a `{phone, message}`-shaped general-purpose sender.
- Webhook receipt of inbound messages or delivery-status callbacks.
