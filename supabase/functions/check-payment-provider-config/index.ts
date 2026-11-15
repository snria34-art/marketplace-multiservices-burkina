// deno-lint-ignore no-import-prefix no-unversioned-import
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// Keep provider configuration checks server-side; expose status flags only.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Provider = "WAVE" | "CINETPAY";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json",
      "cache-control": "no-store",
    },
  });
}

function isConfigured(provider: Provider): boolean {
  if (provider === "WAVE") {
    return Boolean(
      Deno.env.get("WAVE_API_KEY")?.trim() &&
      Deno.env.get("WAVE_WEBHOOK_SECRET")?.trim(),
    );
  }

  return Boolean(
    Deno.env.get("CINETPAY_API_KEY")?.trim() &&
    Deno.env.get("CINETPAY_SITE_ID")?.trim() &&
    Deno.env.get("CINETPAY_SECRET_KEY")?.trim(),
  );
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  // Supabase gateway enforces verify_jwt=true for this function.
  // The explicit check also makes the expected authenticated contract clear.
  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return json({ error: "authentication_required" }, 401);
  }

  let body: { provider?: string };
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "invalid_json" }, 400);
  }

  const provider = body.provider?.trim().toUpperCase();
  if (provider !== "WAVE" && provider !== "CINETPAY") {
    return json({ error: "provider_invalid" }, 400);
  }

  const configured = isConfigured(provider as Provider);

  // Return only a boolean. Never expose environment variable names, values,
  // provider credentials, merchant IDs, or any secret metadata to the client.
  return json({
    provider,
    configured,
    status: configured ? "CONFIGURED" : "NOT_CONFIGURED",
  });
});
