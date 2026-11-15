import "jsr:@supabase/functions-js@^2.116.0/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

function serviceKey(): string {
  const secretContainer = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (secretContainer) {
    try {
      const parsed = JSON.parse(secretContainer);
      if (typeof parsed.default === "string" && parsed.default) {
        return parsed.default;
      }
    } catch {
      // Fall through to the legacy server-only variable.
    }
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

async function readRows(
  admin: ReturnType<typeof createClient>,
  table: string,
  columns: string,
  filter?: (query: any) => any,
): Promise<Record<string, unknown>[]> {
  let query: any = admin.from(table).select(columns).limit(10001);
  if (filter) query = filter(query);
  const { data, error } = await query;
  if (error) {
    throw new Error("PARTNER_NETWORK_QUERY_FAILED:" + table);
  }
  return (data ?? []) as Record<string, unknown>[];
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const bearer = authorization.startsWith("Bearer ");
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const key = serviceKey();

  if (!bearer || !url || !anonKey || !key) {
    return json({ error: "service_not_configured" }, 503);
  }

  const caller = createClient(url, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: authorization } },
  });
  const admin = createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: authData, error: authError } = await caller.auth.getUser();
  const user = authData.user;
  if (authError || !user) {
    return json({ error: "unauthorized" }, 401);
  }

  const [adminRecord, profile] = await Promise.all([
    admin.from("admin_users").select("user_id")
      .eq("user_id", user.id).eq("active", true).maybeSingle(),
    admin.from("profiles").select("status")
      .eq("id", user.id).maybeSingle(),
  ]);
  if (adminRecord.error || profile.error) {
    return json({ error: "authorization_check_failed" }, 500);
  }
  if (!adminRecord.data || profile.data?.status !== "ACTIVE") {
    return json({ error: "admin_access_required" }, 403);
  }

  try {
    const [
      sellers,
      shops,
      providers,
      roles,
      activeAssignments,
      completedAssignments,
      deliveredPackages,
      completedRequests,
    ] = await Promise.all([
      readRows(admin, "sellers", "id,user_id,verification_status"),
      readRows(admin, "shops", "id,seller_id,status,verification_status"),
      readRows(admin, "service_providers", "id,user_id,active,verification_status"),
      readRows(admin, "user_roles", "user_id,role", (query) =>
        query.eq("role", "COURIER")),
      readRows(admin, "delivery_assignments", "courier_id,status", (query) =>
        query.in("status", ["ASSIGNED", "ACCEPTED", "PICKED_UP", "IN_TRANSIT"])),
      readRows(admin, "delivery_assignments", "courier_id,status", (query) =>
        query.eq("status", "COMPLETED")),
      readRows(admin, "order_packages", "order_group_id", (query) =>
        query.eq("status", "DELIVERED")),
      readRows(admin, "service_requests", "service_id,status", (query) =>
        query.eq("status", "COMPLETED")),
    ]);

    const sellerUserIds = sellers.map((row) => String(row.user_id));
    const providerUserIds = providers.map((row) => String(row.user_id));
    const courierUserIds = roles.map((row) => String(row.user_id));
    const accountIds = [...new Set([
      ...sellerUserIds,
      ...providerUserIds,
      ...courierUserIds,
    ])];

    const profiles = accountIds.length === 0
      ? []
      : await readRows(admin, "profiles", "id,status", (query) =>
        query.in("id", accountIds));

    const activeProfiles = new Set(
      profiles.filter((row) => row.status === "ACTIVE")
        .map((row) => String(row.id)),
    );

    const verifiedSellerIds = new Set(
      sellers.filter((row) =>
        row.verification_status === "VERIFIED" &&
        activeProfiles.has(String(row.user_id))
      ).map((row) => String(row.id)),
    );
    const activeVerifiedShops = shops.filter((row) =>
      row.status === "ACTIVE" &&
      row.verification_status === "VERIFIED" &&
      verifiedSellerIds.has(String(row.seller_id))
    );
    const sellersWithActiveShops = new Set(
      activeVerifiedShops.map((row) => {
        const seller = sellers.find((item) =>
          String(item.id) === String(row.seller_id)
        );
        return seller ? String(seller.user_id) : "";
      }).filter((id) => id.length > 0),
    );

    const activeVerifiedProviders = providers.filter((row) =>
      row.active === true &&
      row.verification_status === "VERIFIED" &&
      activeProfiles.has(String(row.user_id))
    );
    const activeCouriers = new Set(
      courierUserIds.filter((id) => activeProfiles.has(id)),
    );
    const couriersOnMission = new Set(
      activeAssignments.map((row) => String(row.courier_id))
        .filter((id) => activeCouriers.has(id)),
    );
    const couriersWithCompletedDeliveries = new Set(
      completedAssignments.map((row) => String(row.courier_id))
        .filter((id) => activeCouriers.has(id)),
    );

    const deliveredGroupIds = [...new Set(
      deliveredPackages.map((row) => String(row.order_group_id))
        .filter((id) => id.length > 0),
    )];
    const deliveredGroups = deliveredGroupIds.length === 0
      ? []
      : await readRows(admin, "order_groups", "id,shop_id", (query) =>
        query.in("id", deliveredGroupIds));
    const deliveredShopIds = [...new Set(
      deliveredGroups.map((row) => String(row.shop_id))
        .filter((id) => id.length > 0),
    )];
    const deliveredSellers = new Set(
      shops.filter((row) =>
        deliveredShopIds.includes(String(row.id)) &&
        verifiedSellerIds.has(String(row.seller_id))
      ).map((row) => {
        const seller = sellers.find((item) =>
          String(item.id) === String(row.seller_id)
        );
        return seller ? String(seller.user_id) : "";
      }).filter((id) => id.length > 0),
    );

    const completedServiceIds = [...new Set(
      completedRequests.map((row) => String(row.service_id))
        .filter((id) => id.length > 0),
    )];
    const completedServices = completedServiceIds.length === 0
      ? []
      : await readRows(admin, "services", "id,provider_id", (query) =>
        query.in("id", completedServiceIds));
    const completedProviderIds = new Set(
      completedServices.map((row) => String(row.provider_id)),
    );
    const providersWithCompletedRequests = new Set(
      providers.filter((row) =>
        completedProviderIds.has(String(row.id)) &&
        activeProfiles.has(String(row.user_id))
      ).map((row) => String(row.user_id)),
    );

    const activePartnerAccounts = new Set([
      ...sellersWithActiveShops,
      ...activeVerifiedProviders.map((row) => String(row.user_id)),
      ...activeCouriers,
    ]);

    const truncated = [
      sellers, shops, providers, roles, activeAssignments,
      completedAssignments, deliveredPackages, completedRequests, profiles,
      deliveredGroups, completedServices,
    ].some((rows) => rows.length > 10000);

    return json({
      generated_at: new Date().toISOString(),
      data_truncated: truncated,
      definitions: {
        active_seller:
          "Compte actif, vendeur vérifié et au moins une boutique active et vérifiée.",
        active_provider:
          "Compte actif, prestataire activé et vérifié.",
        active_courier:
          "Compte actif avec rôle COURIER. Cela ne signifie pas qu'il est disponible en ligne.",
        operational:
          "Au moins une vente livrée, prestation terminée ou livraison terminée dans les données conservées.",
      },
      sellers: {
        registered: sellers.length,
        verified_active: verifiedSellerIds.size,
        with_active_verified_shop: sellersWithActiveShops.size,
        with_delivered_order: deliveredSellers.size,
      },
      shops: {
        registered: shops.length,
        active_verified: activeVerifiedShops.length,
      },
      providers: {
        registered: providers.length,
        active_verified: activeVerifiedProviders.length,
        with_completed_request: providersWithCompletedRequests.size,
      },
      couriers: {
        registered: new Set(courierUserIds).size,
        active_accounts: activeCouriers.size,
        currently_on_mission: couriersOnMission.size,
        with_completed_delivery: couriersWithCompletedDeliveries.size,
      },
      partners: {
        unique_active_accounts: activePartnerAccounts.size,
      },
    });
  } catch (error) {
    console.error("admin-partner-network failed", error);
    return json({ error: "partner_network_unavailable" }, 500);
  }
});
