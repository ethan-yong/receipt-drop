# Remote Supabase setup checklist

After running `supabase db push` and `supabase functions deploy`, three things must be configured on the remote project before the app works end-to-end.

---

## 1. Point the app at the remote project

`.env` defaults to the local Supabase instance. Update these two values to the remote ones (Supabase Dashboard → Settings → API):

```dotenv
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_ANON_KEY=<remote anon key>
```

The project ref is `aufcylqenckxtnpkdyal` (visible in the dashboard URL and in the `functions deploy` output).

---

## 2. Configure Google OAuth on the remote project

`supabase/config.toml` only applies to the local dev stack. On the remote you must enable Google OAuth manually:

1. Go to **Dashboard → Authentication → Providers → Google**.
2. Enable the provider.
3. Paste the same values that are in your `.env`:
   - **Client ID**: `GOOGLE_OAUTH_CLIENT_ID`
   - **Client Secret**: `GOOGLE_OAUTH_CLIENT_SECRET`
4. Add the redirect URL `com.receiptdrop.receiptdrop://login-callback` to the **Authorized redirect URIs** list in your Google Cloud Console OAuth client (alongside whatever web origin you use). This is only used by Apple Sign-In and web/iOS Google sign-in — native Google Sign-In on Android doesn't use a redirect URL.

Android uses **native** Google Sign-In (in-app account picker, no browser) — see `lib/features/auth/auth_screen.dart`'s `_useNativeGoogle`. This needs, on top of the Web client above, an **Android** OAuth client in Google Cloud Console (package name `com.receiptdrop.receipt_drop` + your debug/release SHA-1 fingerprint). Its ID isn't referenced anywhere in app config — Google Play Services matches it automatically by package name + signing fingerprint. Only re-register when the signing key changes.

iOS still uses the browser-OAuth flow above (native iOS Google Sign-In is deferred — see `pending-tasks.md`).

---

## 3. Push edge function secrets to the remote

`supabase/functions/.env` is loaded by the local edge runtime only — it is not deployed with `functions deploy`. Set the secrets on the remote:

```powershell
npx --yes supabase@2.109.1 secrets set `
  OCR_SERVICE_URL=<your hosted OCR API base URL> `
  OCR_SERVICE_SECRET=<must match OCR_SHARED_SECRET on the OCR service> `
  GOOGLE_PLACES_API_KEY=<your Places API key>
```

Verify with:

```powershell
npx --yes supabase@2.109.1 secrets list
```
