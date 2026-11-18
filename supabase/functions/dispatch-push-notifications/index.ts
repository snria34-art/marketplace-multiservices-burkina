import "jsr:@supabase/functions-js@^2.116.0/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { isUnregisteredFcmToken } from "../_shared/fcm_error.ts";

type Json = Record<string, unknown>;

type AdminSchema = {
  Tables: Record<
    string,
    {
      Row: Record<string, unknown>;
      Insert: Record<string, unknown>;
      Update: Record<string, unknown>;
      Relationships: [];
    }
  >;
  Views: Record<
    string,
    {
      Row: Record<string, unknown>;
      Relationships: [];
    }
  >;
  Functions: Record<
    string,
    {
      Args: Record<string, unknown>;
      Returns: unknown;
    }
  >;
  Enums: Record<string, string>;
  CompositeTypes: Record<string, Record<string, unknown>>;
};

type AdminDatabase = { public: AdminSchema };
type AdminClient = SupabaseClient<AdminDatabase, "public">;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

function safeErrorInfo(error: unknown): Record<string, string | number> {
  if (error && typeof error === "object") {
    const value = error as Record<string, unknown>;
    const info: Record<string, string | number> = {
      name: typeof value.name === "string" ? value.name : "UnknownError",
    };
    if (typeof value.code === "string") info.code = value.code;
    if (typeof value.status === "number") info.status = value.status;
    return info;
  }
  return { name: "UnknownError" };
}

function secretKey(): string {
  const raw = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (raw) {
    try {
      const parsed = JSON.parse(raw);
      if (parsed.default) return parsed.default;
    } catch (_) {
      // Ignore malformed secret container and fall back to the standard key.
    }
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/g,
    "",
  );
}

function textBase64Url(value: string): string {
  return base64Url(new TextEncoder().encode(value));
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

async function makeAccessToken(serviceAccount: Json): Promise<string> {
  const clientEmail = String(serviceAccount.client_email ?? "").trim();
  const privateKeyPem = String(serviceAccount.private_key ?? "").replace(
    /\\n/g,
    "\n",
  );
  if (!clientEmail || !privateKeyPem) {
    throw new Error("FCM_SERVICE_ACCOUNT_INVALID");
  }

  const now = Math.floor(Date.now() / 1000);
  const header = textBase64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = textBase64Url(JSON.stringify({
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = header + "." + claim;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKeyPem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(unsigned),
    ),
  );
  const assertion = unsigned + "." + base64Url(signature);

  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const token = await tokenResponse.json().catch(() => null);
  if (!tokenResponse.ok || !token?.access_token) {
    throw new Error("FCM_OAUTH_FAILED");
  }
  return String(token.access_token);
}

function preferenceEnabled(type: string, prefs: Json): boolean {
  const normalized = type.toLowerCase();
  if (
    normalized.includes("order") || normalized.includes("payment") ||
    normalized.includes("commande")
  ) return prefs.orders !== false;
  if (
    normalized.includes("delivery") || normalized.includes("courier") ||
    normalized.includes("livraison")
  ) return prefs.delivery !== false;
  if (normalized.includes("message") || normalized.includes("chat")) {
    return prefs.messages !== false;
  }
  if (
    normalized.includes("promotion") || normalized.includes("coupon") ||
    normalized.includes("promo")
  ) return prefs.promotions !== false;
  if (
    normalized.includes("service") || normalized.includes("mechanic") ||
    normalized.includes("transport")
  ) return prefs.services !== false;
  return true;
}


async function mapWithConcurrency<T, R>(
  items: T[],
  limit: number,
  worker: (item: T) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(items.length);
  let nextIndex = 0;
  const workerCount = Math.min(items.length, Math.max(1, Math.floor(limit)));
  await Promise.all(Array.from({ length: workerCount }, async () => {
    while (true) {
      const index = nextIndex++;
      if (index >= items.length) return;
      results[index] = await worker(items[index]);
    }
  }));
  return results;
}

function fcmData(data: unknown): Record<string, string> {
  if (!data || typeof data !== "object") return {};
  const record = data as Record<string, unknown>;
  const result: Record<string, string> = {};
  for (const [key, value] of Object.entries(record)) {
    if (value === null || value === undefined) continue;
    result[key] = typeof value === "string" ? value : JSON.stringify(value);
  }
  return result;
}

async function sendToToken(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
) {
  const response = await fetch(
    "https://fcm.googleapis.com/v1/projects/" + encodeURIComponent(projectId) +
      "/messages:send",
    {
      method: "POST",
      headers: {
        Authorization: "Bearer " + accessToken,
        "Content-Type": "application/json; UTF-8",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: {
            priority: "HIGH",
            notification: {
              channel_id: "marketplace_default",
              sound: "default",
            },
          },
          apns: {
            payload: { aps: { sound: "default" } },
          },
        },
      }),
    },
  );
  const result = await response.json().catch(() => null);
  return {
    ok: response.ok,
    status: response.status,
    body: result,
  };
}

async function processNotification(
  adminClient: AdminClient,
  accessToken: string,
  projectId: string,
  notificationId: string,
) {
  const claimed = await adminClient.rpc("claim_notification_for_push", {
    p_notification_id: notificationId,
  });

  if (claimed.error) throw claimed.error;
  const claimedRows = Array.isArray(claimed.data) ? claimed.data : [];
  if (claimedRows.length === 0) {
    return {
      id: notificationId,
      skipped: true,
      locked_or_already_processed: true,
    };
  }

  const notification = claimedRows[0] as Json;
  const userId = String(notification.user_id ?? "").trim();
  if (!userId) {
    throw new Error("NOTIFICATION_USER_INVALID");
  }

  try {
    const prefResult = await adminClient
      .from("notification_preferences")
      .select("orders,promotions,messages,delivery,services")
      .eq("user_id", userId)
      .maybeSingle();

    if (prefResult.error) throw prefResult.error;

    const prefs = (prefResult.data ?? {}) as Json;
    if (!preferenceEnabled(String(notification.type ?? ""), prefs)) {
      await adminClient
        .from("notifications")
        .update({
          push_sent_at: new Date().toISOString(),
          push_processing_at: null,
          push_error: "DISABLED_BY_PREFERENCE",
        })
        .eq("id", notificationId);

      return {
        id: notificationId,
        skipped: true,
        preference_disabled: true,
      };
    }

    const deviceResult = await adminClient
      .from("notification_devices")
      .select("id,push_token,platform")
      .eq("user_id", userId)
      .eq("active", true);

    if (deviceResult.error) throw deviceResult.error;

    const devices = (deviceResult.data ?? []) as Json[];
    if (devices.length === 0) {
      await adminClient
        .from("notifications")
        .update({
          push_processing_at: null,
          push_error: "NO_ACTIVE_DEVICE",
          push_attempts: Number(notification.push_attempts ?? 0) + 1,
        })
        .eq("id", notificationId);

      return { id: notificationId, sent: 0, pending: 0 };
    }

    const deviceIds = devices
      .map((device) => String(device.id ?? "").trim())
      .filter((id) => id.length > 0);
    const deliveryRead = await adminClient
      .from("notification_push_deliveries")
      .select("device_id,status")
      .eq("notification_id", notificationId)
      .in("device_id", deviceIds);
    if (deliveryRead.error) throw deliveryRead.error;

    // A notification is complete only when every currently active device has
    // a terminal result. Successful devices are never sent the same message
    // again when another device needs a retry.
    const terminalDeviceIds = new Set(
      ((deliveryRead.data ?? []) as Json[])
        .filter((row) => row.status === "SENT" || row.status === "INVALID")
        .map((row) => String(row.device_id ?? "")),
    );
    const pendingDevices = devices.filter(
      (device) => !terminalDeviceIds.has(String(device.id ?? "")),
    );

    const title = String(notification.title ?? "Marketplace Burkina");
    const body = String(notification.body ?? "Nouvelle notification");
    const data = fcmData(notification.data);
    data.notification_id = notificationId;
    data.type = String(notification.type ?? "general");

    const results = await mapWithConcurrency(pendingDevices, 5, async (device) => {
      const deviceId = String(device.id ?? "").trim();
      const token = String(device.push_token ?? "").trim();
      if (!deviceId) throw new Error("FCM_DEVICE_ID_INVALID");
      if (!token) {
        const invalid = await adminClient
          .from("notification_push_deliveries")
          .upsert({
            notification_id: notificationId,
            device_id: deviceId,
            status: "INVALID",
            last_attempt_at: new Date().toISOString(),
            sent_at: null,
            last_error: "FCM_TOKEN_EMPTY",
          }, { onConflict: "notification_id,device_id" });
        if (invalid.error) throw invalid.error;
        return { token, ok: false, terminal: true, status: 0 };
      }

      const attemptedAt = new Date().toISOString();
      const seed = await adminClient
        .from("notification_push_deliveries")
        .upsert({
          notification_id: notificationId,
          device_id: deviceId,
          status: "PENDING",
          last_attempt_at: attemptedAt,
          last_error: null,
        }, { onConflict: "notification_id,device_id", ignoreDuplicates: true });
      if (seed.error) throw seed.error;

      try {
        const result = await sendToToken(
          accessToken,
          projectId,
          token,
          title,
          body,
          data,
        );

        const invalidToken = isUnregisteredFcmToken(result);
        const deliveryStatus = result.ok
          ? "SENT"
          : invalidToken
          ? "INVALID"
          : "PENDING";
        const completedAt = new Date().toISOString();

        if (invalidToken) {
          const deactivated = await adminClient
            .from("notification_devices")
            .update({ active: false, last_seen_at: completedAt })
            .eq("id", deviceId);
          if (deactivated.error) throw deactivated.error;
        }

        const recorded = await adminClient
          .from("notification_push_deliveries")
          .upsert({
            notification_id: notificationId,
            device_id: deviceId,
            status: deliveryStatus,
            last_attempt_at: completedAt,
            sent_at: result.ok ? completedAt : null,
            last_error: result.ok
              ? null
              : invalidToken
              ? "FCM_TOKEN_INVALID"
              : "FCM_SEND_FAILED",
          }, { onConflict: "notification_id,device_id" });
        if (recorded.error) throw recorded.error;

        return {
          token,
          ok: result.ok,
          terminal: result.ok || invalidToken,
          status: result.status,
        };
      } catch (error) {
        console.error(JSON.stringify({
          event: "fcm_device_send_failed",
          error: safeErrorInfo(error),
        }));
        const recorded = await adminClient
          .from("notification_push_deliveries")
          .upsert({
            notification_id: notificationId,
            device_id: deviceId,
            status: "PENDING",
            last_attempt_at: new Date().toISOString(),
            last_error: "FCM_SEND_FAILED",
          }, { onConflict: "notification_id,device_id" });
        if (recorded.error) throw recorded.error;
        return {
          token,
          ok: false,
          terminal: false,
          status: 0,
        };
      }
    });

    const deliveryState = await adminClient
      .from("notification_push_deliveries")
      .select("device_id,status")
      .eq("notification_id", notificationId)
      .in("device_id", deviceIds);
    if (deliveryState.error) throw deliveryState.error;

    const stateRows = (deliveryState.data ?? []) as Json[];
    const activeDeviceIds = new Set(deviceIds);
    const terminalCount = stateRows.filter((row) =>
      activeDeviceIds.has(String(row.device_id ?? "")) &&
      (row.status === "SENT" || row.status === "INVALID")
    ).length;
    const pendingCount = Math.max(0, devices.length - terminalCount);
    const invalidCount = stateRows.filter((row) =>
      activeDeviceIds.has(String(row.device_id ?? "")) && row.status === "INVALID"
    ).length;
    const sent = results.filter((item) => item.ok).length;
    const errors = results
      .filter((item) => !item.ok && !item.terminal)
      .map(() => "FCM_SEND_FAILED")
      .slice(0, 5);

    await adminClient
      .from("notifications")
      .update({
        push_sent_at: pendingCount === 0 ? new Date().toISOString() : null,
        push_processing_at: null,
        push_attempts: Number(notification.push_attempts ?? 0) + 1,
        push_error: pendingCount > 0 ? "FCM_SEND_FAILED" : null,
      })
      .eq("id", notificationId);

    return {
      id: notificationId,
      sent,
      total: devices.length,
      pending: pendingCount,
      invalid: invalidCount,
      errors,
    };
  } catch (error) {
    await adminClient
      .from("notifications")
      .update({
        push_processing_at: null,
        push_attempts: Number(notification.push_attempts ?? 0) + 1,
        push_error: "PUSH_PROCESSING_FAILED",
      })
      .eq("id", notificationId);

    throw error;
  }
}

Deno.serve(async (req: Request) => {
  let stage = "method";
  try {
    if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

    stage = "configuration";

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const adminKey = secretKey();
  const dispatchSecret = req.headers.get("x-push-dispatch-secret") ?? "";
  if (!url || !adminKey || !dispatchSecret) {
    return json({ error: "not_configured" }, 503);
  }

  stage = "create_admin_client";
  const adminClient: AdminClient = createClient<AdminDatabase, "public">(
    url,
    adminKey,
    {
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );
  stage = "verify_dispatch_secret";
  const check = await adminClient.rpc("verify_push_dispatch_secret", {
    p_candidate: dispatchSecret,
  });
  if (check.error) {
    console.error(JSON.stringify({
      event: "push_dispatch_secret_verification_failed",
      error: safeErrorInfo(check.error),
    }));
    return json({ error: "secret_verification_unavailable" }, 503);
  }
  if (check.data !== true) return json({ error: "unauthorized" }, 401);

  stage = "fcm_service_account_configuration";
  const serviceAccountRaw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON") ?? "";
  if (!serviceAccountRaw) {
    console.error(JSON.stringify({
      event: "fcm_service_account_missing",
      hasFcmProjectId: Boolean(Deno.env.get("FCM_PROJECT_ID")),
    }));
    return json({ error: "fcm_not_configured" }, 503);
  }
  let serviceAccount: Json;
  try {
    serviceAccount = JSON.parse(serviceAccountRaw) as Json;
  } catch (error) {
    console.error(JSON.stringify({
      event: "fcm_service_account_json_invalid",
      error: safeErrorInfo(error),
    }));
    return json({ error: "fcm_service_account_invalid" }, 503);
  }

  const projectId = String(
    serviceAccount.project_id ?? Deno.env.get("FCM_PROJECT_ID") ?? "",
  ).trim();
  if (!projectId) {
    console.error(JSON.stringify({ event: "fcm_project_id_missing" }));
    return json({ error: "fcm_project_id_missing" }, 503);
  }

  stage = "fcm_oauth";
  let accessToken: string;
  try {
    accessToken = await makeAccessToken(serviceAccount);
  } catch (error) {
    console.error(JSON.stringify({
      event: "fcm_oauth_failed",
      error: safeErrorInfo(error),
    }));
    return json({ error: "fcm_auth_failed" }, 503);
  }

  stage = "parse_payload";
  let payload: { notification_id?: string };
  try {
    payload = await req.json();
  } catch (_) {
    payload = {};
  }

  if (payload.notification_id) {
    stage = "process_single_notification";
    const result = await processNotification(
      adminClient,
      accessToken,
      projectId,
      payload.notification_id,
    );
    return json(result);
  }

  stage = "fetch_pending_notifications";
  const pending = await adminClient
    .from("notifications")
    .select("id")
    .is("push_sent_at", null)
    .lt("push_attempts", 20)
    .gte(
      "created_at",
      new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString(),
    )
    .order("created_at", { ascending: true })
    .limit(50);
  if (pending.error) {
    console.error(JSON.stringify({
      event: "push_pending_fetch_failed",
      error: safeErrorInfo(pending.error),
    }));
    return json({ error: "notifications_fetch_failed" }, 500);
  }

  stage = "process_pending_notifications";
  const ids = ((pending.data ?? []) as Json[]).map((row) => String(row.id));
  const results = await mapWithConcurrency(ids, 5, async (id) => {
    try {
      return await processNotification(adminClient, accessToken, projectId, id);
    } catch (error) {
      console.error(JSON.stringify({
        event: "push_notification_processing_failed",
        notificationId: id,
        error: safeErrorInfo(error),
      }));
      return { id, error: "PUSH_PROCESSING_FAILED" };
    }
  });
  return json({ processed: results.length, results });
  } catch (error) {
    console.error(JSON.stringify({
      event: "push_dispatch_unhandled_error",
      stage,
      error: safeErrorInfo(error),
    }));
    return json({ error: "push_dispatch_internal_error", stage }, 500);
  }
});
