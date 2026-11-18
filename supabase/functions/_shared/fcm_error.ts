export function isUnregisteredFcmToken(result: {
  ok: boolean;
  body?: unknown;
}): boolean {
  if (result.ok || !result.body || typeof result.body !== "object") {
    return false;
  }

  const error = (result.body as Record<string, unknown>).error;
  if (!error || typeof error !== "object") return false;

  const details = (error as Record<string, unknown>).details;
  if (!Array.isArray(details)) return false;

  return details.some((detail) => {
    if (!detail || typeof detail !== "object") return false;
    const value = detail as Record<string, unknown>;
    return value["@type"] ===
        "type.googleapis.com/google.firebase.fcm.v1.FcmError" &&
      value.errorCode === "UNREGISTERED";
  });
}
