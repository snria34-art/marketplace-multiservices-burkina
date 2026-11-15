import {
  isReusableWaveCheckoutSession,
  isXofCurrency,
  parseCinetPayXofAmount,
  parsePositiveSafeIntegerAmount,
  prepareWavePaymentEvent,
  shouldPersistPaymentEvent,
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

Deno.test("CinetPay XOF amounts respect the provider minimum and increment", () => {
  assert(parseCinetPayXofAmount(100) === 100, "minimum amount");
  assert(parseCinetPayXofAmount("125") === 125, "multiple of five");

  const invalid: unknown[] = [
    0,
    5,
    95,
    99,
    101,
    "100.00",
    "1e2",
    true,
    null,
    Number.MAX_SAFE_INTEGER + 1,
  ];
  for (const value of invalid) {
    assert(
      parseCinetPayXofAmount(value) === null,
      `expected CinetPay amount to be rejected: ${String(value)}`,
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

Deno.test("Wave checkout reuse requires a valid unexpired session", () => {
  const now = Date.UTC(2026, 0, 1);
  const reusable = {
    id: "cos-test",
    wave_launch_url: "https://pay.wave.com/c/cos-test",
    checkout_status: "open",
    payment_status: "processing",
    when_expires: "2026-01-01T01:00:00Z",
  };
  assert(isReusableWaveCheckoutSession(reusable, now), "open session reused");

  const retryableFailure = {
    ...reusable,
    // A retryable payment_failed webhook may leave the retrieved Checkout
    // Session open/processing while last_payment_error records the attempt.
    checkout_status: "open",
    payment_status: "processing",
    last_payment_error: { code: "insufficient-funds" },
  };
  assert(
    isReusableWaveCheckoutSession(retryableFailure, now),
    "open session with a retryable failed attempt remains reusable",
  );

  const terminalStates = [
    { ...reusable, checkout_status: "complete" },
    { ...reusable, checkout_status: "expired" },
    { ...reusable, payment_status: "succeeded" },
    { ...reusable, payment_status: "cancelled" },
    { ...reusable, checkout_status: "failed" },
    { ...reusable, payment_status: "failed" },
    { ...reusable, when_expires: "2025-12-31T23:59:59Z" },
    { ...reusable, wave_launch_url: "https://example.com/fake" },
    { ...reusable, when_expires: undefined },
  ];

  for (const session of terminalStates) {
    assert(
      !isReusableWaveCheckoutSession(session, now),
      "terminal, expired or untrusted checkout must not be reused",
    );
  }
});

Deno.test("only terminal payment states are sent to the SQL event processor", () => {
  assert(shouldPersistPaymentEvent("SUCCEEDED"), "success is terminal");
  assert(shouldPersistPaymentEvent("FAILED"), "failure is terminal");
  assert(shouldPersistPaymentEvent("CANCELLED"), "cancellation is terminal");
  assert(!shouldPersistPaymentEvent("PROCESSING"), "processing is non-terminal");
  assert(!shouldPersistPaymentEvent(null), "missing state is rejected");
  assert(!shouldPersistPaymentEvent("UNKNOWN"), "unknown state is rejected");
});
