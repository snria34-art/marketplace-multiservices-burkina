import { buildProviderEventId } from "./provider_event_identity.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("Wave uses its stable event id", async () => {
  const a = await buildProviderEventId("wave", '{"id":"evt_1"}', "evt_1");
  const b = await buildProviderEventId("wave", '{"id":"evt_1","retry":true}', "evt_1");
  assert(a === "wave:id:evt_1" && a === b, "Wave event id stays stable across retries");
});

Deno.test("Wave falls back to a deterministic body hash", async () => {
  const body = '{"type":"checkout.session.completed","data":{"id":"cos_1"}}';
  const a = await buildProviderEventId("wave", body);
  const b = await buildProviderEventId("wave", body);
  const c = await buildProviderEventId("wave", body + " ");
  assert(a === b && a !== c && a.startsWith("wave:sha256:"), "SHA-256 fallback");
});

Deno.test("CinetPay hashes canonical signed fields, not raw form ordering", async () => {
  const canonical = "site1txn1date10001000XOFsignatureACCEPTED00";
  const a = await buildProviderEventId("cinetpay", "a=1&b=2", undefined, canonical);
  const b = await buildProviderEventId("cinetpay", "b=2&a=1", undefined, canonical);
  const c = await buildProviderEventId("cinetpay", "a=1&b=2", undefined, canonical + "REFUSED");
  assert(a === b && a !== c, "canonical fingerprint is stable and status-sensitive");
});

Deno.test("provider namespaces cannot collide", async () => {
  const a = await buildProviderEventId("wave", '{"id":"same"}', "same");
  const b = await buildProviderEventId("cinetpay", '{"id":"same"}');
  assert(a !== b, "provider namespaces differ");
});

Deno.test("empty callback identity material is rejected", async () => {
  let failed = false;
  try {
    await buildProviderEventId("cinetpay", "");
  } catch {
    failed = true;
  }
  assert(failed, "empty material rejected");
});
