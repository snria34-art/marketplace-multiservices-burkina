import {
  isXofCurrency,
  parsePositiveSafeIntegerAmount,
  waveCheckoutEventStatus,
} from "./payment_validation.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("accepts positive safe integer provider amounts", () => {
  assert(parsePositiveSafeIntegerAmount(1500) === 1500, "number amount");
  assert(parsePositiveSafeIntegerAmount("1500") === 1500, "string amount");
  assert(parsePositiveSafeIntegerAmount(" 00050 ") === 50, "trimmed integer");
});

Deno.test("rejects missing, coercible and non-integer provider amounts", () => {
  const invalid: unknown[] = [
    undefined,
    null,
    true,
    false,
    "",
    " ",
    "1.5",
    "1.0",
    "1e3",
    "+10",
    "-10",
    0,
    -1,
    NaN,
    Infinity,
    Number.MAX_SAFE_INTEGER + 1,
  ];

  for (const value of invalid) {
    assert(
      parsePositiveSafeIntegerAmount(value) === null,
      `expected amount to be rejected: ${String(value)}`,
    );
  }
});

Deno.test("accepts only an explicit XOF currency string", () => {
  assert(isXofCurrency("XOF"), "uppercase XOF");
  assert(isXofCurrency(" xof "), "normalized XOF");
  assert(!isXofCurrency(undefined), "missing currency");
  assert(!isXofCurrency(null), "null currency");
  assert(!isXofCurrency(0), "numeric currency");
  assert(!isXofCurrency(true), "boolean currency");
  assert(!isXofCurrency("USD"), "other currency");
});

Deno.test("Wave failed attempts remain processing until a session succeeds", () => {
  assert(
    waveCheckoutEventStatus("checkout.session.completed") === "SUCCEEDED",
    "completed event settles only through success path",
  );
  assert(
    waveCheckoutEventStatus("checkout.session.payment_failed") === "PROCESSING",
    "failed attempt is non-terminal and may be retried",
  );
  assert(
    waveCheckoutEventStatus("test.test_event") === null,
    "unrelated event is ignored",
  );
  assert(
    waveCheckoutEventStatus(undefined) === null,
    "missing event type is ignored",
  );
});
