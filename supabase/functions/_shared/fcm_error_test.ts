import { assertEquals } from "jsr:@std/assert@1";
import { isUnregisteredFcmToken } from "./fcm_error.ts";

Deno.test("marks an explicitly UNREGISTERED FCM token as invalid", () => {
  assertEquals(isUnregisteredFcmToken({
    ok: false,
    body: { error: { details: [{
      "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
      errorCode: "UNREGISTERED",
    }] } },
  }), true);
});

Deno.test("does not deactivate a token for an unrelated HTTP 404", () => {
  assertEquals(isUnregisteredFcmToken({
    ok: false,
    body: { error: { status: "NOT_FOUND", details: [] } },
  }), false);
});

Deno.test("does not deactivate a token for INVALID_ARGUMENT", () => {
  assertEquals(isUnregisteredFcmToken({
    ok: false,
    body: { error: { details: [{
      "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
      errorCode: "INVALID_ARGUMENT",
    }] } },
  }), false);
});

Deno.test("does not mark a successful response as invalid", () => {
  assertEquals(isUnregisteredFcmToken({ ok: true, body: {} }), false);
});
