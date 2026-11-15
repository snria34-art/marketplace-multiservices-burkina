// deno-lint-ignore no-import-prefix no-unversioned-import
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

function publishableKey(): string {
  const raw = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  if (raw) {
    try {
      const parsed = JSON.parse(raw);
      if (parsed.default) return parsed.default;
    } catch (_) {
      // Ignore malformed optional configuration and use the fallback environment variable.
    }
  }
  return Deno.env.get("SUPABASE_ANON_KEY") ?? "";
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

  const auth = req.headers.get("Authorization");
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = publishableKey();
  const adminKey = secretKey();
  if (!auth || !url || !key || !adminKey) {
    return json({ error: "supabase_not_configured" }, 503);
  }

  let body: { refund_id?: string };
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "invalid_json" }, 400);
  }
  const refundId = body.refund_id?.trim();
  if (!refundId) return json({ error: "refund_required" }, 400);

  const userClient = createClient(url, key, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: refundRows, error: beginError } = await userClient.rpc(
    "admin_begin_refund",
    {
      p_refund_id: refundId,
    },
  );
  if (beginError) return json({ error: "refund_action_failed" }, 409);
  if (!Array.isArray(refundRows) || refundRows.length === 0) {
    return json({ error: "refund_not_found" }, 404);
  }

  const refund = refundRows[0] as Record<string, unknown>;
  const provider = String(refund.provider ?? "");
  const providerReference = String(refund.provider_reference ?? "").trim();
  const amount = Number(refund.amount);
  if (
    !provider || !providerReference || !Number.isFinite(amount) || amount <= 0
  ) {
    return json({ error: "refund_provider_data_invalid" }, 409);
  }

  const adminClient = createClient(url, adminKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Wave's Checkout refund endpoint refunds the entire checkout payment; it
  // does not accept a partial amount. Never send a partial local refund to it.
  if (provider === "WAVE") {
    const { data: payment, error: paymentLookupError } = await adminClient
      .from("payments")
      .select("amount,currency")
      .eq("id", String(refund.payment_id ?? ""))
      .maybeSingle();

    if (paymentLookupError || !payment) {
      const { data: resetRow, error: resetError } = await adminClient
        .from("refunds")
        .update({ status: "APPROVED" })
        .eq("id", refundId)
        .eq("status", "PROCESSING")
        .select("id")
        .maybeSingle();

      if (resetError || !resetRow) {
        return json({
          error: "refund_state_update_failed",
          refund_id: refundId,
        }, 500);
      }

      return json({
        error: "refund_payment_lookup_failed",
        refund_id: refundId,
        manual_required: true,
      }, 503);
    }

    const capturedAmount = Number(payment.amount);
    if (
      payment.currency !== "XOF" ||
      refund.currency !== payment.currency ||
      !Number.isFinite(capturedAmount) ||
      capturedAmount !== amount
    ) {
      const { data: resetRow, error: resetError } = await adminClient
        .from("refunds")
        .update({
          status: "APPROVED",
          reason: (
            String(refund.reason ?? "") +
            " | Wave Checkout ne prend en charge que le remboursement intégral du paiement ; montant différent, validation manuelle requise."
          ).slice(0, 1000),
        })
        .eq("id", refundId)
        .eq("status", "PROCESSING")
        .select("id")
        .maybeSingle();

      if (resetError || !resetRow) {
        return json({
          error: "refund_state_update_failed",
          refund_id: refundId,
        }, 500);
      }

      return json({
        error: "wave_partial_refund_not_supported",
        refund_id: refundId,
        manual_required: true,
      }, 409);
    }
  }

  if (provider !== "WAVE") {
    const { data: manualReset, error: manualUpdateError } = await adminClient
      .from("refunds")
      .update({
        status: "APPROVED",
        reason: (
          String(refund.reason ?? "") +
          " | Exécution automatique non disponible pour " +
          provider +
          "; traitement fournisseur manuel requis."
        ).slice(0, 1000),
      })
      .eq("id", refundId)
      .eq("status", "PROCESSING")
      .select("id")
      .maybeSingle();

    if (manualUpdateError || !manualReset) {
      return json({
        error: "refund_state_update_failed",
        refund_id: refundId,
      }, 500);
    }

    return json({
      ok: false,
      manual_required: true,
      provider,
      refund_id: refundId,
      message: "Remboursement fournisseur manuel requis.",
    }, 409);
  }

  const waveApiKey = Deno.env.get("WAVE_API_KEY");
  if (!waveApiKey) {
    const { data: resetRow, error: resetError } = await adminClient
      .from("refunds")
      .update({ status: "APPROVED" })
      .eq("id", refundId)
      .eq("status", "PROCESSING")
      .select("id")
      .maybeSingle();
    if (resetError || !resetRow) {
      return json({
        error: "refund_state_update_failed",
        refund_id: refundId,
      }, 500);
    }
    return json({ error: "wave_not_configured", refund_id: refundId }, 503);
  }

  let waveResponse: Response;
  try {
    waveResponse = await fetch(
      "https://api.wave.com/v1/checkout/sessions/" +
        encodeURIComponent(providerReference) +
        "/refund",
      {
        method: "POST",
        headers: { Authorization: "Bearer " + waveApiKey },
      },
    );
  } catch (_) {
    // The provider may have received the request before the connection failed.
    // Keep the refund in PROCESSING so it cannot be blindly submitted again.
    return json({
      error: "wave_refund_result_unknown",
      refund_id: refundId,
      manual_reconciliation_required: true,
    }, 502);
  }

  if (!waveResponse.ok) {
    // A 5xx may be returned after the provider has accepted the refund.
    // Keep it PROCESSING for manual reconciliation; never blindly retry it.
    const providerResultUnknown = waveResponse.status >= 500;
    const { data: failureUpdate, error: failureUpdateError } = await adminClient
      .from("refunds")
      .update({
        status: providerResultUnknown ? "PROCESSING" : "FAILED",
        reason: (
          String(refund.reason ?? "") +
          " | Wave refund returned HTTP status " +
          waveResponse.status +
          (providerResultUnknown
            ? "; provider result requires manual reconciliation."
            : ".")
        ).slice(0, 1000),
      })
      .eq("id", refundId)
      .eq("status", "PROCESSING")
      .select("id")
      .maybeSingle();

    if (failureUpdateError || !failureUpdate) {
      return json({
        error: "refund_state_update_failed",
        provider_status: waveResponse.status,
        refund_id: refundId,
      }, 500);
    }

    return json({
      error: providerResultUnknown
        ? "wave_refund_result_unknown"
        : "wave_refund_failed",
      provider_status: waveResponse.status,
      refund_id: refundId,
      manual_reconciliation_required: providerResultUnknown,
    }, 502);
  }

  const { error: completeError } = await adminClient.rpc("complete_refund", {
    p_refund_id: refundId,
    p_provider_reference: "WAVE_REFUND:" + providerReference,
  });

  if (completeError) {
    return json({
      error: "refund_completion_failed",
      refund_provider_confirmed: true,
      refund_id: refundId,
    }, 409);
  }

  return json({
    ok: true,
    refund_id: refundId,
    provider: "WAVE",
    amount,
    status: "COMPLETED",
  });
});
