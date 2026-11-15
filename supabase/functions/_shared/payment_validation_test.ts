import {
  isXofCurrency,
  parsePositiveSafeIntegerAmount,
  prepareWavePaymentEvent,
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

Deno.test("Wave payment_failed payload may omit provider amount and currency", () => {
  const prepared = prepareWavePaymentEvent(
    "PROCESSING",
    undefined,
    undefined,
    1250,
  );

  assert(prepared !== null, "retryable failure should be recorded");
  assert(prepared.status === "PROCESSING", "failure must not settle payment");
  assert(prepared.amount === 1250, "trusted local amount satisfies RPC only");
});

Deno.test("Wave completed event requires exact provider amount and XOF", () => {
  const valid = prepareWavePaymentEvent(
    "SUCCEEDED",
    "1250",
    "XOF",
    1250,
  );
  assert(valid !== null, "matching XOF success");
  assert(valid.status === "SUCCEEDED", "successful callback status");
  assert(valid.amount === 1250, "provider amount retained");

  const invalid: Array<[unknown, unknown, unknown]> = [
    [undefined, undefined, 1250],
    ["1250", "USD", 1250],
    ["1251", "XOF", 1250],
    [true, "XOF", 1250],
    ["1250", "XOF", "1250.50"],
  ];

  for (const [providerAmount, currency, localAmount] of invalid) {
    assert(
      prepareWavePaymentEvent(
        "SUCCEEDED",
        providerAmount,
        currency,
        localAmount,
      ) === null,
      "invalid successful callback data must be rejected",
    );
  }
});
