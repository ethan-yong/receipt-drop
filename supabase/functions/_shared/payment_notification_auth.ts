/** Shared-secret check for payment-notification-proxy — the one Edge
 * Function in this project with `verify_jwt = false` (see
 * supabase/config.toml). Its only caller is this app's own native Android
 * code (no live user session available there), so a single build-time
 * secret takes the place of the usual per-user JWT check, mirroring
 * services/ocr-api's own verify_ocr_secret trust model one hop further out.
 * See docs/system/decisions.md for why, and the caveat about revisiting
 * this before any public distribution. */
export function isValidPaymentNotificationSecret(
  provided: string | null,
): boolean {
  const expected = Deno.env.get("PAYMENT_NOTIFICATION_PROXY_SECRET");
  if (!expected || !provided) return false;
  return timingSafeEqual(provided, expected);
}

// Plain string equality leaks timing information proportional to the
// matching prefix length; a fixed-length comparison avoids that for a
// secret compared on every request.
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}
