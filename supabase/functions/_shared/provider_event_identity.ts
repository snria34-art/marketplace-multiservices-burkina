export type PaymentProvider = "wave" | "cinetpay";

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/** Wave's event.id is preferred; CinetPay uses canonical fields authenticated by x-token. */
export async function buildProviderEventId(
  provider: PaymentProvider,
  rawBody: string,
  nativeEventId?: unknown,
  canonicalFingerprint?: string,
): Promise<string> {
  if (provider === "wave" && isNonEmptyString(nativeEventId)) {
    return "wave:id:" + nativeEventId.trim();
  }
  const material = provider === "cinetpay" && isNonEmptyString(canonicalFingerprint)
    ? canonicalFingerprint
    : rawBody;
  if (!isNonEmptyString(material)) {
    throw new TypeError("provider_event_identity_material_required");
  }
  return provider + ":sha256:" + await sha256Hex(material);
}
