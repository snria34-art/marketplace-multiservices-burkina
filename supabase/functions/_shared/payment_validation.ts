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

/** Accept the provider currency only when it explicitly identifies XOF. */
export function isXofCurrency(value: unknown): boolean {
  return typeof value === "string" && value.trim().toUpperCase() === "XOF";
}
