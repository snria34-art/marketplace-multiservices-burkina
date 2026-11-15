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

  const reusableCheckoutState = checkoutStatus === "open" ||
    checkoutStatus === "failed";
  const reusablePaymentState = paymentStatus === "processing" ||
    paymentStatus === "failed";

  return reusableCheckoutState && reusablePaymentState;
}

/** Accept the provider currency only when it explicitly identifies XOF. */
export function isXofCurrency(value: unknown): boolean {
  return typeof value === "string" && value.trim().toUpperCase() === "XOF";
}
