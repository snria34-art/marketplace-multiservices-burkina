import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const url = Deno.env.get("SUPABASE_URL") ?? "";
const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") ??
  (() => {
    try {
      return JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}").default ?? "";
    } catch {
      return "";
    }
  })();
const serviceKey = (() => {
  try {
    const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    if (secretKeys.default) return secretKeys.default;
  } catch (_) {}
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
})();

function response(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

async function timed(component: string, probe: () => Promise<{ status: string; details?: Record<string, unknown> }>) {
  const started = Date.now();
  try {
    const result = await probe();
    return {
      component,
      status: result.status,
      response_ms: Date.now() - started,
      details: result.details ?? {},
    };
  } catch (error) {
    return {
      component,
      status: "DOWN",
      response_ms: Date.now() - started,
      details: { error: error instanceof Error ? error.message : "probe_failed" },
    };
  }
}

async function serviceRest(path: string) {
  return await fetch(url + "/rest/v1/" + path, {
    headers: {
      apikey: serviceKey,
      Authorization: "Bearer " + serviceKey,
    },
    signal: AbortSignal.timeout(8000),
  });
}

async function hmacHex(message: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(signature)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return response(405, { error: "method_not_allowed" });
  if (!url || !publishableKey || !serviceKey) return response(503, { error: "supabase_secrets_missing" });

  const monitorSecret = req.headers.get("x-platform-monitor-secret") ?? "";
  if (monitorSecret) {
    const secretCheck = await fetch(url + "/rest/v1/rpc/check_platform_monitor_secret", {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: "Bearer " + serviceKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ p_secret: monitorSecret }),
      signal: AbortSignal.timeout(8000),
    });
    if (!secretCheck.ok || (await secretCheck.json()) !== true) {
      return response(401, { error: "invalid_monitor_secret" });
    }
  } else {
    const authorization = req.headers.get("Authorization") ?? "";
    if (!authorization.startsWith("Bearer ")) return response(401, { error: "authentication_required" });

    const userResponse = await fetch(url + "/auth/v1/user", {
      headers: { apikey: publishableKey, Authorization: authorization },
      signal: AbortSignal.timeout(8000),
    });
    if (!userResponse.ok) return response(401, { error: "invalid_session" });

    const adminResponse = await fetch(url + "/rest/v1/rpc/is_admin_actor", {
      method: "POST",
      headers: {
        apikey: publishableKey,
        Authorization: authorization,
        "Content-Type": "application/json",
      },
      body: "{}",
      signal: AbortSignal.timeout(8000),
    });
    if (!adminResponse.ok || (await adminResponse.json()) !== true) {
      return response(403, { error: "admin_access_required" });
    }
  }

  const results: Array<Record<string, unknown>> = [];

  results.push(await timed("SUPABASE_AUTH", async () => {
    const res = await fetch(url + "/auth/v1/health", {
      headers: { apikey: publishableKey },
      signal: AbortSignal.timeout(8000),
    });
    return { status: res.ok ? "UP" : res.status < 500 ? "DEGRADED" : "DOWN", details: { http_status: res.status } };
  }));

  results.push(await timed("SUPABASE_REST", async () => {
    const res = await serviceRest("profiles?select=id&limit=1");
    return { status: res.ok ? "UP" : res.status < 500 ? "DEGRADED" : "DOWN", details: { http_status: res.status } };
  }));

  results.push(await timed("SUPABASE_STORAGE", async () => {
    const bucketNames = ["avatars", "documents", "order-feedback-media", "product-media", "shop-media"];
    const bucketResults = await Promise.all(bucketNames.map(async (bucket) => {
      const res = await fetch(url + "/storage/v1/bucket/" + bucket, {
        headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey },
        signal: AbortSignal.timeout(8000),
      });
      return { bucket, status: res.ok ? "UP" : res.status < 500 ? "DEGRADED" : "DOWN", http_status: res.status };
    }));
    const status = bucketResults.every((item) => item.status === "UP")
      ? "UP"
      : bucketResults.some((item) => item.status === "DOWN")
        ? "DOWN"
        : "DEGRADED";
    return { status, details: { buckets: bucketResults } };
  }));

  results.push(await timed("NETWORK", async () => {
    const res = await fetch("https://www.cloudflare.com/cdn-cgi/trace", {
      signal: AbortSignal.timeout(8000),
    });
    return { status: res.ok ? "UP" : res.status < 500 ? "DEGRADED" : "DOWN", details: { http_status: res.status, target: "cloudflare_trace" } };
  }));

  results.push(await timed("EDGE_FUNCTIONS", async () => {
    const res = await fetch(url + "/functions/v1/analyze-product", {
      method: "OPTIONS",
      headers: { "Origin": "https://app.local", "Access-Control-Request-Method": "POST" },
      signal: AbortSignal.timeout(8000),
    });
    return { status: res.ok ? "UP" : res.status < 500 ? "DEGRADED" : "DOWN", details: { http_status: res.status, target: "analyze-product" } };
  }));

  const waveKey = Deno.env.get("WAVE_API_KEY") ?? "";
  const waveSigning = Deno.env.get("WAVE_SIGNING_SECRET") ?? "";
  if (!waveKey) {
    results.push({ component: "WAVE", status: "NOT_CONFIGURED", response_ms: null, details: { reason: "WAVE_API_KEY_missing" } });
  } else {
    const paymentRes = await serviceRest("payments?select=provider_reference,status&provider=eq.WAVE&provider_reference=not.is.null&order=updated_at.desc&limit=1");
    const payments = paymentRes.ok ? await paymentRes.json() : [];
    const reference = Array.isArray(payments) && payments.length ? String(payments[0].provider_reference ?? "") : "";
    if (!reference) {
      results.push({ component: "WAVE", status: "NOT_TESTED", response_ms: null, details: { reason: "no_recent_wave_reference" } });
    } else {
      results.push(await timed("WAVE", async () => {
        const headers: Record<string, string> = { Authorization: "Bearer " + waveKey };
        if (waveSigning) {
          const timestamp = Math.floor(Date.now() / 1000).toString();
          headers["Wave-Signature"] = "t=" + timestamp + ",v1=" + await hmacHex(timestamp, waveSigning);
        }
        const res = await fetch("https://api.wave.com/v1/checkout/sessions/" + encodeURIComponent(reference), {
          headers,
          signal: AbortSignal.timeout(10000),
        });
        return {
          status: res.ok ? "UP" : res.status < 500 ? "DEGRADED" : "DOWN",
          details: { http_status: res.status, checked_existing_reference: true },
        };
      }));
    }
  }

  const cinetpayKey = Deno.env.get("CINETPAY_API_KEY") ?? "";
  const cinetpaySite = Deno.env.get("CINETPAY_SITE_ID") ?? "";
  if (!cinetpayKey || !cinetpaySite) {
    results.push({ component: "CINETPAY", status: "NOT_CONFIGURED", response_ms: null, details: { reason: "CINETPAY_API_KEY_or_SITE_ID_missing" } });
  } else {
    const paymentRes = await serviceRest("payments?select=provider_reference,status&provider=eq.CINETPAY&provider_reference=not.is.null&order=updated_at.desc&limit=1");
    const payments = paymentRes.ok ? await paymentRes.json() : [];
    const reference = Array.isArray(payments) && payments.length ? String(payments[0].provider_reference ?? "") : "";
    if (!reference) {
      results.push({ component: "CINETPAY", status: "NOT_TESTED", response_ms: null, details: { reason: "no_recent_cinetpay_reference" } });
    } else {
      results.push(await timed("CINETPAY", async () => {
        const res = await fetch("https://api-checkout.cinetpay.com/v2/payment/check", {
          method: "POST",
          headers: { "Content-Type": "application/json", "User-Agent": "Marketplace-Multiservices-Burkina/1.0" },
          body: JSON.stringify({ apikey: cinetpayKey, site_id: cinetpaySite, transaction_id: reference }),
          signal: AbortSignal.timeout(10000),
        });
        return {
          status: res.ok ? "UP" : res.status < 500 ? "DEGRADED" : "DOWN",
          details: { http_status: res.status, checked_existing_reference: true },
        };
      }));
    }
  }

  const fcmServiceAccountRaw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON") ?? "";
  const fcmProjectIdEnv = Deno.env.get("FCM_PROJECT_ID") ?? "";
  if (!fcmServiceAccountRaw.trim()) {
    results.push({
      component: "FCM",
      status: "NOT_CONFIGURED",
      response_ms: null,
      details: {
        reason: "FCM_SERVICE_ACCOUNT_JSON_missing",
        has_fcm_project_id: Boolean(fcmProjectIdEnv.trim()),
      },
    });
  } else {
    try {
      const parsedServiceAccount = JSON.parse(fcmServiceAccountRaw);
      const serviceAccount =
        parsedServiceAccount && typeof parsedServiceAccount === "object" &&
          !Array.isArray(parsedServiceAccount)
          ? parsedServiceAccount as Record<string, unknown>
          : {};
      const fcmProjectId = String(
        serviceAccount.project_id ?? fcmProjectIdEnv,
      ).trim();
      const hasClientEmail =
        typeof serviceAccount.client_email === "string" &&
        serviceAccount.client_email.trim().length > 0;
      const hasPrivateKey =
        typeof serviceAccount.private_key === "string" &&
        serviceAccount.private_key.trim().length > 0;

      if (!hasClientEmail || !hasPrivateKey) {
        results.push({
          component: "FCM",
          status: "DEGRADED",
          response_ms: null,
          details: {
            reason: "FCM_SERVICE_ACCOUNT_JSON_INVALID",
            has_project_id: Boolean(fcmProjectId),
            has_client_email: hasClientEmail,
            has_private_key: hasPrivateKey,
          },
        });
      } else if (!fcmProjectId) {
        results.push({
          component: "FCM",
          status: "NOT_CONFIGURED",
          response_ms: null,
          details: { reason: "FCM_PROJECT_ID_missing" },
        });
      } else {
        results.push({
          component: "FCM",
          status: "NOT_TESTED",
          response_ms: null,
          details: {
            configuration_fields_present: true,
            live_delivery_tested: false,
          },
        });
      }
    } catch (_) {
      results.push({
        component: "FCM",
        status: "DEGRADED",
        response_ms: null,
        details: { reason: "FCM_SERVICE_ACCOUNT_JSON_invalid_json" },
      });
    }
  }

  const openAiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  if (!openAiKey) {
    results.push({ component: "OPENAI", status: "NOT_CONFIGURED", response_ms: null, details: { reason: "OPENAI_API_KEY_missing" } });
  } else {
    results.push(await timed("OPENAI", async () => {
      const res = await fetch("https://api.openai.com/v1/models", {
        headers: { Authorization: "Bearer " + openAiKey },
        signal: AbortSignal.timeout(10000),
      });
      return { status: res.ok ? "UP" : res.status < 500 ? "DEGRADED" : "DOWN", details: { http_status: res.status } };
    }));
  }

  const record = await fetch(url + "/rest/v1/rpc/record_platform_health_checks", {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: "Bearer " + serviceKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p_results: results }),
    signal: AbortSignal.timeout(10000),
  });
  if (!record.ok) {
    return response(502, { error: "health_results_not_recorded", checks: results });
  }

  return response(200, { ok: true, checks: results });
});
