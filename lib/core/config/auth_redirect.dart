/// OAuth redirect URL for Supabase on mobile (Android/iOS deep link).
///
/// Must match [additional_redirect_urls] in `supabase/config.toml` and the
/// intent-filter / URL scheme in native manifests.
///
/// No underscores: GoTrue validates redirect_to with Go's url.Parse, which
/// rejects underscores in URI schemes and silently falls back to site_url.
const oauthRedirectUrl = 'com.receiptdrop.receiptdrop://login-callback';
