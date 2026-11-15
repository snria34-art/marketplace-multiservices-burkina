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

/** Accept the provider currency only when it explicitly identifies XOF. */
export function isXofCurrency(value: unknown): boolean {
  return typeof value === "string" && value.trim().toUpperCase() === "XOF";
}
