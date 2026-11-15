/**
 * Parse an integer amount supplied by a payment provider.
 *
 * Provider JSON must contain a number or a string made only of decimal digits.
 * Booleans, null, decimals, exponent notation and unsafe integers are rejected.
 */
export function parsePositiveSafeIntegerAmount(value: unknown): number | null {
  let amount: number;

  if (typeof value === "number") {
    amount = value;
  } else if (typeof value === "string" && /^\d+$/.test(value.trim())) {
    amount = Number(value.trim());
  } else {
    return null;
  }

  return Number.isSafeInteger(amount) && amount > 0 ? amount : null;
}

/** Only unsettled payments may start or reuse a checkout session. */
export function isPaymentCheckoutEligibleStatus(
  value: unknown,
): value is "PENDING" | "PROCESSING" {
  if (typeof value !== "string") return false;
  const status = value.trim().toUpperCase();
  return status === "PENDING" || status === "PROCESSING";
}

/**
 * Classify Wave Checkout events without treating a retryable attempt failure
 * as a terminal payment failure. Wave documents that multiple payment_failed
 * events may occur before the same session eventually succeeds.
 */
export function waveCheckoutEventStatus(
  eventType: unknown,
): "SUCCEEDED" | "PROCESSING" | null {
  if (eventType === "checkout.session.completed") return "SUCCEEDED";
  if (eventType === "checkout.session.payment_failed") return "PROCESSING";
  return null;
}

/**
 * Prepare the numeric arguments for the Wave payment RPC.
 *
 * Failed checkout attempts are informational and may omit amount/currency.
 * They are persisted as PROCESSING using only the trusted local amount.
 * Successful callbacks require a matching provider amount and explicit XOF.
 */
export function prepareWavePaymentEvent(
  status: "SUCCEEDED" | "PROCESSING",
  providerAmount: unknown,
  providerCurrency: unknown,
  localAmount: unknown,
): { status: "SUCCEEDED" | "PROCESSING"; amount: number } | null {
  const expectedAmount = parsePositiveSafeIntegerAmount(localAmount);
  if (expectedAmount === null) return null;

  if (status === "PROCESSING") {
    return { status, amount: expectedAmount };
  }

  const actualAmount = parsePositiveSafeIntegerAmount(providerAmount);
  if (
    actualAmount === null ||
    actualAmount !== expectedAmount ||
    !isXofCurrency(providerCurrency)
  ) {
    return null;
  }

  return { status, amount: actualAmount };
}

/**
 * Reuse a Wave checkout only while its provider session is still valid.
 *
 * A failed attempt may still be retried on the same checkout session. A
 * completed/expired/cancelled session must not be handed back to the customer.
 */
export function isReusableWaveCheckoutSession(
  value: unknown,
  nowMs = Date.now(),
): value is Record<string, unknown> & { wave_launch_url: string } {
  if (typeof value !== "object" || value === null) return false;

  const session = value as Record<string, unknown>;
  const launchUrl = session.wave_launch_url;
  if (
    typeof launchUrl !== "string" ||
    !launchUrl.startsWith("https://pay.wave.com/")
  ) {
    return false;
  }

  const expiry = Date.parse(String(session.when_expires ?? ""));
  if (!Number.isFinite(expiry) || expiry <= nowMs) return false;

  const checkoutStatus = String(session.checkout_status ?? "")
    .trim()
    .toLowerCase();
  const paymentStatus = String(session.payment_status ?? "")
    .trim()
    .toLowerCase();

  // The GET Checkout Session object has a narrower enum than webhook events:
  // checkout_status is open/complete/expired and payment_status is
  // processing/cancelled/succeeded. A payment_failed webhook is retryable,
  // but its event payload must not be confused with the GET session object.
  return checkoutStatus === "open" && paymentStatus === "processing";
}

/**
 * Only terminal payment states should be sent to the SQL event processor.
 * Intermediate PROCESSING notifications are acknowledged by the webhook but
 * do not consume the unique provider_reference slot in payment_events.
 */
export function shouldPersistPaymentEvent(
  status: unknown,
): status is "SUCCEEDED" | "FAILED" | "CANCELLED" {
  return status === "SUCCEEDED" ||
    status === "FAILED" ||
    status === "CANCELLED";
}

/**
 * CinetPay XOF checkout amounts must be positive whole amounts, at least
 * 100 XOF, and divisible by five.
 */
export function parseCinetPayXofAmount(value: unknown): number | null {
  const amount = parsePositiveSafeIntegerAmount(value);
  if (amount === null || amount < 100 || amount % 5 !== 0) return null;
  return amount;
}

/**
 * Recognized CinetPay non-terminal transaction statuses. An unknown status
 * is deliberately not considered reusable: the caller must reconcile it.
 */
export function isCinetPayPendingStatus(value: unknown): boolean {
  if (typeof value !== "string") return false;
  const status = value.trim().toUpperCase();
  return status === "WAITING_FOR_CUSTOMER" ||
    status === "WAITING_CUSTOMER_TO_VALIDATE" ||
    status === "PENDING" ||
    status === "INITIATED" ||
    status === "SECURE_PAYMENT_WAITING_CONFIRMATION";
}

/** Accept only HTTPS checkout links hosted by a CinetPay domain. */
export function isTrustedCinetPayCheckoutUrl(value: unknown): value is string {
  if (typeof value !== "string" || value.trim() !== value) return false;
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase();
    const trustedHost = host === "cinetpay.com" ||
      host.endsWith(".cinetpay.com") ||
      host === "cinetpay.co" ||
      host.endsWith(".cinetpay.co");
    return url.protocol === "https:" &&
      trustedHost &&
      url.username === "" &&
      url.password === "";
  } catch {
    return false;
  }
}

/**
 * A stored CinetPay checkout is reusable only when the provider's status API
 * confirms an awaiting-customer transaction with the exact local XOF amount.
 */
export function isReusableCinetPayPaymentCheck(
  value: unknown,
  localAmount: unknown,
  localCurrency: unknown,
): boolean {
  if (typeof value !== "object" || value === null) return false;
  const response = value as Record<string, unknown>;
  const data = response.data;
  if (typeof data !== "object" || data === null) return false;

  const result = data as Record<string, unknown>;
  const expectedAmount = parseCinetPayXofAmount(localAmount);
  const actualAmount = parseCinetPayXofAmount(result.amount);
  return String(response.code ?? "").trim() === "00" &&
    isCinetPayPendingStatus(result.status) &&
    expectedAmount !== null &&
    actualAmount === expectedAmount &&
    isXofCurrency(localCurrency) &&
    isXofCurrency(result.currency);
}

/** Accept the provider currency only when it explicitly identifies XOF. */
export function isXofCurrency(value: unknown): boolean {
  return typeof value === "string" && value.trim().toUpperCase() === "XOF";
}
