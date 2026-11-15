// deno-lint-ignore no-import-prefix no-unversioned-import
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { isXofCurrency, parsePositiveSafeIntegerAmount, prepareWavePaymentEvent, waveCheckoutEventStatus } from "../_shared/payment_validation.ts";
import { buildProviderEventId } from "../_shared/provider_event_identity.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

async function hmacHex(message: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const buf = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message),
  );
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function secretKey(): string {
  const raw = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (raw) {
    try {
      const parsed = JSON.parse(raw);
      if (parsed.default) return parsed.default;
    } catch (_) {
      // Ignore malformed optional configuration and use the fallback environment variable.
    }
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const webhookSecret = Deno.env.get("WAVE_WEBHOOK_SECRET") ?? "";
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const adminKey = secretKey();
  if (!webhookSecret || !url || !adminKey) {
    return json({ error: "webhook_not_configured" }, 503);
  }

  const rawBody = await req.text();
  const signatureHeader = req.headers.get("Wave-Signature") ?? "";
  const parts: Record<string, string> = {};
  for (const part of signatureHeader.split(",")) {
    const index = part.indexOf("=");
    if (index > 0) parts[part.slice(0, index)] = part.slice(index + 1);
  }

  const timestamp = Number(parts.t);
  const now = Math.floor(Date.now() / 1000);
  if (!Number.isInteger(timestamp) || Math.abs(now - timestamp) > 300) {
    return json({ error: "invalid_signature_timestamp" }, 401);
  }

  const signatures = signatureHeader
    .split(",")
    .filter((part) => part.trim().startsWith("v1="))
    .map((part) => part.trim().slice(3));

  if (signatures.length === 0) {
    const authorization = req.headers.get("Authorization") ?? "";
    const bearer = authorization.startsWith("Bearer ")
      ? authorization.slice(7).trim()
      : "";
    if (!bearer || !constantTimeEqual(bearer, webhookSecret)) {
      return json({ error: "invalid_signature" }, 401);
    }
  } else {
    const expected = await hmacHex(String(timestamp) + rawBody, webhookSecret);
    if (
      !signatures.some((signature) => constantTimeEqual(expected, signature))
    ) {
      return json({ error: "invalid_signature" }, 401);
    }
  }

  let event: Record<string, unknown>;
  try {
    event = JSON.parse(rawBody);
  } catch (_) {
    return json({ error: "invalid_json" }, 400);
  }

  const eventType = String(event.type ?? "").trim();
  const data = (event.data ?? {}) as Record<string, unknown>;
  if (!eventType) return json({ error: "invalid_event" }, 400);

  const status = waveCheckoutEventStatus(eventType);
  if (!status) return json({ ok: true, ignored: true, event_type: eventType });

  const supabase = createClient(url, adminKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const clientReference = String(data.client_reference ?? "").trim();
  const sessionId = String(data.id ?? "").trim();
  const transactionId = String(data.transaction_id ?? "").trim();

  if (!sessionId) {
    return json({ error: "wave_session_reference_missing" }, 422);
  }

  let paymentId = clientReference;
  if (!paymentId && sessionId) {
    const { data: rows } = await supabase
      .from("payments")
      .select("id")
      .eq("provider", "WAVE")
      .eq("provider_reference", sessionId)
      .limit(1);
    paymentId = rows?.[0]?.id ? String(rows[0].id) : "";
  }

  if (!paymentId && transactionId) {
    const { data: rows } = await supabase
      .from("payments")
      .select("id")
      .eq("provider", "WAVE")
      .eq("provider_reference", transactionId)
      .limit(1);
    paymentId = rows?.[0]?.id ? String(rows[0].id) : "";
  }

  if (!paymentId) return json({ error: "payment_not_resolved" }, 404);

  const { data: payment, error: paymentError } = await supabase
    .from("payments")
    .select("amount,currency,provider")
    .eq("id", paymentId)
    .maybeSingle();

  if (paymentError || !payment) {
    return json({ error: "payment_not_found" }, 404);
  }

  if (
    String(payment.provider ?? "").trim().toUpperCase() !== "WAVE" ||
    String(payment.currency ?? "").trim().toUpperCase() !== "XOF"
  ) {
    return json({ error: "payment_local_data_invalid" }, 409);
  }

  // This helper admits a missing provider amount/currency only for a
  // non-settling PROCESSING event. A successful event must match the provider
  // amount and XOF currency exactly before it can reach the SQL state machine.
  const preparedEvent = prepareWavePaymentEvent(
    status,
    data.amount,
    data.currency,
    payment.amount,
  );
  if (!preparedEvent) {
    if (status === "SUCCEEDED") {
      const providerAmount = parsePositiveSafeIntegerAmount(data.amount);
      if (providerAmount === null || !isXofCurrency(data.currency)) {
        return json({ error: "payment_amount_or_currency_invalid" }, 422);
      }
      return json({ error: "payment_amount_or_currency_mismatch" }, 409);
    }
    return json({ error: "payment_local_data_invalid" }, 409);
  }
  const amountForRpc = preparedEvent.amount;

  const providerEventId = await buildProviderEventId("wave", rawBody, event.id);
  const eventPayload = {
    ...data,
    gateway_reference: sessionId,
    wave_event_id: typeof event.id === "string" ? event.id : null,
  };

  const { data: result, error } = await supabase.rpc("process_payment_event", {
    p_payment_id: paymentId,
    p_event_type: eventType,
    p_status: preparedEvent.status,
    p_provider_reference: sessionId,
    p_amount: amountForRpc,
    p_provider_event_id: providerEventId,
    p_payload: eventPayload,
  });
  if (error) {
    return json({ error: "payment_event_processing_failed" }, 409);
  }

  return json({ ok: true, result, status: preparedEvent.status });
});
