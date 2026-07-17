/** Cloudflare Access Service Token headers for calling ocr-api's production
 * hostname (ocr.receipt-drop.org), which Access gates on top of X-OCR-Secret.
 * Returns an empty object when either value is missing (local dev, where
 * ocr-api isn't behind Access) — see docs/decisions.md. */
export function cfAccessHeaders(
  clientId?: string,
  clientSecret?: string,
): Record<string, string> {
  return clientId && clientSecret
    ? {
      "CF-Access-Client-Id": clientId,
      "CF-Access-Client-Secret": clientSecret,
    }
    : {};
}
