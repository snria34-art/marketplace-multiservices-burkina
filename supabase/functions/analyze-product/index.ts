import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceKey = (() => {
  try {
    const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    if (secretKeys.default) return secretKeys.default;
  } catch (_) {}
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
})();
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "";
const openAiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
const model = Deno.env.get("OPENAI_VISION_MODEL") ?? "gpt-4o-mini";

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function base64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}

async function serviceRest(path: string, init: RequestInit = {}) {
  return await fetch(supabaseUrl + "/rest/v1/" + path, {
    ...init,
    headers: {
      apikey: serviceKey,
      Authorization: "Bearer " + serviceKey,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!supabaseUrl || !serviceKey || !anonKey) {
    return json(503, { error: "supabase_function_secrets_missing" });
  }
  if (!openAiKey) {
    return json(503, {
      error: "ai_provider_not_configured",
      message: "OPENAI_API_KEY must be configured as a Supabase Edge Function secret.",
    });
  }

  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return json(401, { error: "authentication_required" });
  }

  try {
    const authResponse = await fetch(supabaseUrl + "/auth/v1/user", {
      headers: { apikey: anonKey, Authorization: authorization },
    });
    if (!authResponse.ok) return json(401, { error: "invalid_session" });
    const user = await authResponse.json();
    const userId = String(user.id ?? "");
    if (!userId) return json(401, { error: "invalid_session" });

    const input = await req.json();
    const productId = String(input.product_id ?? "");
    if (!/^[0-9a-f-]{36}$/i.test(productId)) {
      return json(400, { error: "invalid_product_id" });
    }

    const productResponse = await serviceRest(
      "products?id=eq." + encodeURIComponent(productId) + "&select=id,shop_id,name,description,status",
    );
    if (!productResponse.ok) return json(502, { error: "product_lookup_failed" });
    const products = await productResponse.json();
    if (!Array.isArray(products) || products.length !== 1) {
      return json(404, { error: "product_not_found" });
    }
    const product = products[0];

    const adminResponse = await fetch(supabaseUrl + "/rest/v1/rpc/is_admin_actor", {
      method: "POST",
      headers: {
        apikey: anonKey,
        Authorization: authorization,
        "Content-Type": "application/json",
      },
      body: "{}",
    });
    const isAdmin = adminResponse.ok && (await adminResponse.json()) === true;

    if (!isAdmin) {
      const shopResponse = await serviceRest(
        "shops?id=eq." + encodeURIComponent(product.shop_id) + "&select=seller_id",
      );
      if (!shopResponse.ok) return json(502, { error: "shop_lookup_failed" });
      const shops = await shopResponse.json();
      const sellerId = Array.isArray(shops) && shops.length ? shops[0].seller_id : null;
      if (!sellerId) return json(403, { error: "seller_access_denied" });

      const sellerResponse = await serviceRest(
        "sellers?id=eq." + encodeURIComponent(sellerId) + "&select=user_id",
      );
      if (!sellerResponse.ok) return json(502, { error: "seller_lookup_failed" });
      const sellers = await sellerResponse.json();
      if (!Array.isArray(sellers) || !sellers.some((s: any) => s.user_id === userId)) {
        return json(403, { error: "seller_access_denied" });
      }
      if (product.status !== "PENDING_REVIEW") {
        return json(409, { error: "product_must_be_submitted_for_review" });
      }
    }

    const claimResponse = await fetch(supabaseUrl + "/rest/v1/rpc/claim_ai_product_scan", {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: "Bearer " + serviceKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ p_product_id: productId }),
    });
    if (!claimResponse.ok) return json(502, { error: "ai_scan_lock_failed" });
    if ((await claimResponse.json()) !== true) {
      return json(429, { error: "product_recently_scanned" });
    }

    const imagesResponse = await serviceRest(
      "product_images?product_id=eq." + encodeURIComponent(productId) + "&select=storage_path,image_role,alt_text,sort_order&order=sort_order.asc",
    );
    if (!imagesResponse.ok) return json(502, { error: "product_images_lookup_failed" });
    const images = await imagesResponse.json();
    if (!Array.isArray(images) || images.length === 0) {
      return json(422, { error: "product_images_required" });
    }

    const productImages = images.filter((item: any) => item.image_role === "PRODUCT");
    const packagingImages = images.filter((item: any) => item.image_role === "PACKAGING");
    const labelImages = images.filter((item: any) => item.image_role === "LABEL");
    const selectedImages = [
      ...productImages.slice(0, 2),
      ...packagingImages.slice(0, 1),
      ...labelImages.slice(0, 1),
      ...productImages.slice(2, 4),
    ].slice(0, 4);
    const imageParts: Array<Record<string, unknown>> = [];
    const imageRoles: Array<Record<string, unknown>> = [];
    for (const item of selectedImages) {
      const path = String(item.storage_path ?? "");
      if (!path.startsWith("products/" + productId + "/")) continue;
      const encodedPath = path.split("/").map(encodeURIComponent).join("/");
      const imageResponse = await fetch(
        supabaseUrl + "/storage/v1/object/product-media/" + encodedPath,
        { headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey } },
      );
      if (!imageResponse.ok) continue;
      const bytes = new Uint8Array(await imageResponse.arrayBuffer());
      if (bytes.length === 0 || bytes.length > 5 * 1024 * 1024) continue;
      const mime = imageResponse.headers.get("content-type") ?? "image/jpeg";
      if (!mime.startsWith("image/")) continue;
      imageParts.push({
        type: "image_url",
        image_url: {
          url: "data:" + mime + ";base64," + base64(bytes),
          detail: "high",
        },
      });
      imageRoles.push({
        role: item.image_role ?? "PRODUCT",
        alt_text: item.alt_text ?? null,
      });
    }

    if (imageParts.length === 0) {
      return json(422, { error: "no_readable_product_images" });
    }

    const prompt = "Examine cette annonce d'une marketplace au Burkina Faso.\n" +
      "Nom: " + String(product.name ?? "") + "\n" +
      "Description: " + String(product.description ?? "") + "\n" +
      "Rôles des images dans le même ordre: " + JSON.stringify(imageRoles) + "\n\n" +
      "Tu es un outil de pré-modération, pas un juge final. Compare précisément le produit visible, les emballages, les étiquettes et les allégations de la description.\n" +
      "Règles:\n" +
      "- Distingue une vraie arme fonctionnelle d'un jouet clairement identifiable (pistolet-jouet, pistolet à eau, jouet en plastique). Un jouet clairement identifiable ne doit pas être classé comme arme réelle; signale-le en REVIEW si ambigu.\n" +
      "- Signale les armes réelles, drogues contrôlées, poisons, substances toxiques et produits manifestement dangereux.\n" +
      "- Les pesticides et insecticides ne sont pas automatiquement interdits: classe-les en REVIEW pour contrôle administratif et autorisation éventuelle.\n" +
      "- Les aphrodisiaques et produits à allégations sexuelles ou médicales non vérifiées doivent être signalés pour examen, sans conclusion juridique automatique.\n" +
      "- Pour les cosmétiques, examine les étiquettes et les ingrédients lisibles; signale les substances dangereuses ou les allégations manifestement risquées.\n" +
      "- Détecte les écarts entre l'article photographié, son emballage, l'étiquette, la description et le nom.\n" +
      "- Ne prétends pas lire un texte illisible. Si aucune image d'emballage/étiquette n'est fournie, indique-le.\n" +
      "- Si l'image ne permet pas de conclure, choisis REVIEW.\n" +
      "- Ne refuse jamais définitivement une annonce et ne suspends jamais un vendeur. Toute décision finale appartient à l'administration.\n" +
      "Réponds uniquement avec le JSON demandé, en français.";

    const aiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + openAiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        temperature: 0.1,
        max_tokens: 700,
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "burkina_product_moderation",
            strict: true,
            schema: {
              type: "object",
              additionalProperties: false,
              properties: {
                decision: { type: "string", enum: ["CLEAR", "REVIEW", "HIGH_RISK"] },
                confidence: { type: "number", minimum: 0, maximum: 1 },
                critical: { type: "boolean" },
                categories: { type: "array", items: { type: "string" } },
                mismatches: { type: "array", items: { type: "string" } },
                summary: { type: "string" },
                image_description_match: { type: "boolean" },
                packaging_observed: { type: "boolean" },
              },
              required: [
                "decision",
                "confidence",
                "critical",
                "categories",
                "mismatches",
                "summary",
                "image_description_match",
                "packaging_observed",
              ],
            },
          },
        },
        messages: [
          {
            role: "system",
            content: "Tu effectues une analyse visuelle prudente de produits. Tu ne prends jamais de décision de sanction définitive.",
          },
          {
            role: "user",
            content: [
              { type: "text", text: prompt },
              ...imageParts,
            ],
          },
        ],
      }),
    });

    if (!aiResponse.ok) {
      const errorText = await aiResponse.text();
      return json(502, { error: "ai_provider_request_failed", detail: errorText.slice(0, 500) });
    }

    const aiData = await aiResponse.json();
    const rawContent = aiData.choices?.[0]?.message?.content;
    if (typeof rawContent !== "string") return json(502, { error: "ai_response_missing" });
    const result = JSON.parse(rawContent);

    const recordResponse = await fetch(supabaseUrl + "/rest/v1/rpc/record_ai_product_analysis", {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: "Bearer " + serviceKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        p_product_id: productId,
        p_model: model,
        p_result: result,
        p_image_count: imageParts.length,
      }),
    });
    if (!recordResponse.ok) {
      const errorText = await recordResponse.text();
      return json(502, { error: "ai_result_record_failed", detail: errorText.slice(0, 500) });
    }

    return json(200, {
      ok: true,
      product_id: productId,
      scan_id: await recordResponse.json(),
      decision: result.decision,
      confidence: result.confidence,
      summary: result.summary,
      image_count: imageParts.length,
    });
  } catch (error) {
    return json(500, {
      error: "analysis_failed",
      message: error instanceof Error ? error.message : "unexpected_error",
    });
  }
});
