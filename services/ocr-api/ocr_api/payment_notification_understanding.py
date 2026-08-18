"""LLM payment-notification-understanding step: turns a short Android
notification string (from a Malaysian banking or e-wallet app) into a
normalized transaction record.

This is a deliberately SEPARATE pipeline from receipt understanding
(ocr_api/receipt_understanding.py) — different input shape (a one-line
notification vs. an OCR'd receipt/screenshot), different prompt, different
schema, different parser/validation. It shares only genuinely generic LLM
client infrastructure from ocr_api/llm_gateway.py: provider config
resolution, the chat-completions URL builder, JSON-from-a-chatty-model
extraction, confidence clamping, and the retry/timeout/non-2xx HTTP-call
handling. It does NOT reuse the receipt-understanding prompt, schema,
classification, OCR logic, line-item extraction, or bank-receipt parsing.

Called from `POST /understand-payment-notification` (see ocr_api/main.py),
itself only ever called by the `payment-notification-proxy` Supabase edge
function on behalf of this app's own native Android code (see
android/app/src/main/kotlin/.../paymentdetect/PaymentNotificationClient.kt) —
never by an end user directly.
"""

from __future__ import annotations

import json
import logging

import httpx
from pydantic import BaseModel

from ocr_api.llm_gateway import (
    LlmGatewayError,
    as_positive_float_or_none,
    as_str_or_none,
    call_chat_completion,
    clamp01,
    extract_json_object,
    resolve_llm_config,
)

logger = logging.getLogger("ocr_api.payment_notification_understanding")

# Short, single-shot budget — the native overlay is waiting synchronously on
# this call before it can show anything, unlike the receipt path's 25s
# (which runs during an already-async OCR upload, nothing is blocked on it
# visually). Kept as its own named constant rather than reusing
# receipt_understanding.LLM_TIMEOUT_SECONDS since the two pipelines' latency
# budgets are independent and may need to diverge further later.
PAYMENT_NOTIFICATION_LLM_TIMEOUT_SECONDS = 8.0
PAYMENT_NOTIFICATION_LLM_MAX_TOKENS = 300

TRANSACTION_TYPES = {"payment", "transfer_out", "transfer_in", "unknown"}


class PaymentNotificationUnderstandingRequest(BaseModel):
    notification_text: str
    source_package: str | None = None
    posted_at: str | None = None


class PaymentNotificationUnderstandingResponse(BaseModel):
    transaction_type: str
    merchant: str | None = None
    counterparty: str | None = None
    amount: float | None = None
    currency: str = "MYR"
    confidence: float = 0.0


PAYMENT_NOTIFICATION_SYSTEM_PROMPT = (
    "You are a payment-notification understanding engine for Malaysian "
    "banking and e-wallet apps (Maybank, Touch 'n Go eWallet, CIMB, Google "
    "Wallet, and others). The input is the raw text of ONE Android "
    "notification — a short, one- or two-line natural-language string, NOT "
    "a full receipt.\n\n"
    "Respond with ONE JSON object and nothing else — no markdown, no "
    "explanation — with exactly these keys:\n\n"
    '"transaction_type" (string): exactly one of "payment", '
    '"transfer_out", "transfer_in", or "unknown".\n'
    '  - "payment": a card/wallet purchase at a merchant '
    '(e.g. "RM18.50 spent at Starbucks", "Purchase of RM45.00 at Grab", '
    '"Payment successful", "Debit RM75.00").\n'
    '  - "transfer_out": the user sent/transferred money to someone '
    '(e.g. "RM100.00 transferred to John Tan", "I sent RM100 to John", '
    '"DuitNow transfer to Ali RM50").\n'
    '  - "transfer_in": the user received money '
    '(e.g. "RM50 received from Sarah", "Credit RM50.00").\n'
    '  - "unknown": the text does not clearly describe a completed '
    "financial transaction, or you cannot confidently tell which of the "
    'three types it is. ALWAYS prefer "unknown" over guessing.\n\n'
    '"merchant" (string or null): for "payment" only — the business that '
    "was paid. null for every other transaction_type, and null if not "
    "identifiable.\n\n"
    '"counterparty" (string or null): for "transfer_out"/"transfer_in" '
    "only — the person or entity money was sent to or received from. null "
    'for "payment"/"unknown", and null if not identifiable.\n\n'
    '"amount" (number or null): the transaction amount, as a plain number '
    "(e.g. 18.50), with NO currency symbol or thousands separator. null if "
    "no amount is clearly stated — never estimate or infer an amount from "
    "context.\n\n"
    '"currency" (string): the ISO-4217-style currency code, e.g. "MYR". '
    'Use "MYR" when the text uses "RM" or no currency is stated (this app '
    "is Malaysia-only) — but if the text explicitly names a different "
    'currency (e.g. "USD", "SGD"), use that instead. Never guess a '
    "currency other than MYR without explicit textual evidence.\n\n"
    '"confidence" (number, 0 to 1): your confidence that transaction_type '
    "and amount are both correct. Use a low value (below 0.3) when the "
    "text is ambiguous, generic, or you had to guess at any field.\n\n"
    "STRICT RULES — do not violate any of these:\n"
    "1. Never invent a merchant or counterparty name that is not present "
    "in the text.\n"
    "2. Never invent or estimate an amount — if there is no clear numeric "
    'amount, set "amount" to null and strongly consider "unknown".\n'
    "3. Never invent a transaction_type — if genuinely ambiguous, use "
    '"unknown".\n'
    "4. Prefer information explicitly present in the text over any "
    "inference.\n"
    "5. A notification that merely MENTIONS money (a bill reminder, a "
    "cashback promo, a balance-only alert with no completed transaction) "
    'is "unknown", not a real transaction.'
)


def parse_payment_notification_understanding(
    raw: str,
) -> PaymentNotificationUnderstandingResponse | None:
    """Parses + validates a raw LLM completion. Every field is coerced
    defensively — the LLM's output is a hint, this function is the
    authority. Returns None only when there's no parseable JSON at all.

    A typed result ("payment"/"transfer_out"/"transfer_in") with no valid
    numeric amount is downgraded to "unknown" with a null amount — this
    service must never hand back a typed-but-amountless transaction, since
    the caller treats "typed + has an amount" as the sole signal that it's
    safe to show the user a category-picker overlay for it.
    """
    json_text = extract_json_object(raw)
    if json_text is None:
        return None
    try:
        obj = json.loads(json_text)
    except json.JSONDecodeError:
        return None
    if not isinstance(obj, dict):
        return None

    raw_type = as_str_or_none(obj.get("transaction_type"))
    transaction_type = (
        raw_type.lower()
        if raw_type and raw_type.lower() in TRANSACTION_TYPES
        else "unknown"
    )

    merchant = as_str_or_none(obj.get("merchant"))
    counterparty = as_str_or_none(obj.get("counterparty"))
    amount = as_positive_float_or_none(obj.get("amount"))
    # Zero is not a meaningful transaction amount for this domain (unlike
    # receipts, where a free line item can legitimately be 0) — treat it the
    # same as "no amount".
    if amount is not None and amount <= 0:
        amount = None

    raw_currency = as_str_or_none(obj.get("currency"))
    currency = (
        raw_currency.upper() if raw_currency and raw_currency.isalpha() else "MYR"
    )

    confidence = clamp01(obj.get("confidence"))

    # Never hand back a typed-but-amountless result — downgrade to unknown.
    if transaction_type != "unknown" and amount is None:
        transaction_type = "unknown"
        merchant = None
        counterparty = None

    # Field/type coupling: merchant only makes sense for "payment",
    # counterparty only for the two transfer types. Drop whichever doesn't
    # apply rather than trust the model to have already done so.
    if transaction_type != "payment":
        merchant = None
    if transaction_type not in ("transfer_out", "transfer_in"):
        counterparty = None

    return PaymentNotificationUnderstandingResponse(
        transaction_type=transaction_type,
        merchant=merchant,
        counterparty=counterparty,
        amount=amount,
        currency=currency,
        confidence=confidence,
    )


def _build_messages(
    notification_text: str, source_package: str | None
) -> list[dict[str, str]]:
    user_content = notification_text.strip()
    if source_package:
        user_content = f"(source app package: {source_package})\n{user_content}"
    return [
        {"role": "system", "content": PAYMENT_NOTIFICATION_SYSTEM_PROMPT},
        {"role": "user", "content": user_content},
    ]


async def call_payment_notification_understanding(
    notification_text: str,
    source_package: str | None,
    posted_at: str | None,
    *,
    http_client: httpx.AsyncClient,
) -> PaymentNotificationUnderstandingResponse:
    """Calls the LLM gateway and returns a validated understanding, or
    raises [LlmGatewayError]. No fallback — the caller (the
    /understand-payment-notification route) surfaces any failure as an
    error response; it never silently invents a transaction on failure."""
    del posted_at  # not currently used by the prompt; kept in the request
    # shape for forward compatibility (e.g. future recency-based prompting)
    # without changing the wire contract.

    cfg = resolve_llm_config()
    messages = _build_messages(notification_text, source_package)

    logger.info(
        "calling LLM gateway for payment-notification understanding "
        "provider=%s model=%s sourcePackage=%s textChars=%d",
        cfg.provider,
        cfg.model_name,
        source_package,
        len(notification_text),
    )
    content = await call_chat_completion(
        messages,
        cfg=cfg,
        http_client=http_client,
        max_tokens=PAYMENT_NOTIFICATION_LLM_MAX_TOKENS,
        timeout_seconds=PAYMENT_NOTIFICATION_LLM_TIMEOUT_SECONDS,
    )

    understanding = parse_payment_notification_understanding(content)
    if understanding is None:
        logger.error(
            "LLM response could not be parsed into a payment-notification "
            "understanding: %r",
            content[:1000],
        )
        raise LlmGatewayError(
            "llm_unparseable_content",
            "no actionable JSON in LLM response",
            content[:1000],
        )

    logger.info(
        "payment-notification understanding parsed — transactionType=%r "
        "amount=%r currency=%r confidence=%.2f",
        understanding.transaction_type,
        understanding.amount,
        understanding.currency,
        understanding.confidence,
    )
    return understanding
