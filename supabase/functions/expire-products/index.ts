import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "unauthorized" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "server_configuration_missing" }, 500);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);
  const token = authorization.slice("Bearer ".length);
  const { data: userData, error: userError } =
    await supabase.auth.getUser(token);

  if (userError || !userData.user) {
    return json({ error: "unauthorized" }, 401);
  }

  const userId = userData.user.id;
  const [{ data: admin, error: adminError }, { data: profile, error: profileError }] =
    await Promise.all([
      supabase
        .from("admin_users")
        .select("user_id")
        .eq("user_id", userId)
        .eq("active", true)
        .maybeSingle(),
      supabase
        .from("profiles")
        .select("id")
        .eq("id", userId)
        .eq("status", "ACTIVE")
        .maybeSingle(),
    ]);

  if (adminError || profileError) {
    return json({ error: "authorization_check_failed" }, 500);
  }
  if (!admin || !profile) {
    return json({ error: "forbidden" }, 403);
  }

  const today = new Date().toISOString().slice(0, 10);
  const { data, error } = await supabase
    .from("products")
    .update({ status: "INACTIVE" })
    .eq("is_expirable", true)
    .lt("expiry_date", today)
    .eq("status", "ACTIVE")
    .select("id");

  if (error) {
    return json({ error: "product_expiration_failed" }, 500);
  }

  return json({
    expired_products_deactivated: data?.length ?? 0,
    checked_at: new Date().toISOString(),
  });
});
