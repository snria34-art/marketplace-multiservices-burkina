import { paymentReturnMessage } from "./payment_return_message.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("payment redirect never claims that the payment is confirmed", () => {
  const message = paymentReturnMessage("success");
  assert(message.includes("ne confirme pas"), "success redirect is non-authoritative");
  assert(message.includes("côté serveur"), "server confirmation is authoritative");
});

Deno.test("payment error redirect does not overwrite or assume saved payment state", () => {
  const message = paymentReturnMessage("error");
  assert(message.includes("ne modifie pas le statut enregistré"), "redirect does not mutate status");
});

Deno.test("unknown redirect states use the neutral message", () => {
  const message = paymentReturnMessage("unexpected");
  assert(message.includes("statut confirmé côté serveur"), "unknown state is neutral");
  assert(
    paymentReturnMessage(null) === message,
    "non-string state is treated as unknown",
  );
});
