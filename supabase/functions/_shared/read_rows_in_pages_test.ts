import { readRowsInPages } from "./read_rows_in_pages.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("readRowsInPages collects rows across full pages", async () => {
  const source = Array.from({ length: 1234 }, (_, index) => index);
  const rows = await readRowsInPages(
    async (offset, limit) => source.slice(offset, offset + limit),
    { pageSize: 500, maxRows: 10001 },
  );

  assert(rows.length === source.length, "all source rows should be returned");
  assert(rows[0] === 0, "first row should be retained");
  assert(rows.at(-1) === 1233, "last row should be retained");
});

Deno.test("readRowsInPages continues after a server-capped short page", async () => {
  const source = Array.from({ length: 117 }, (_, index) => index);
  const offsets: number[] = [];
  const rows = await readRowsInPages(
    async (offset, requested) => {
      offsets.push(offset);
      // Simulate a project-level PostgREST max-rows cap lower than requested.
      return source.slice(offset, offset + Math.min(requested, 17));
    },
    { pageSize: 50, maxRows: 1000 },
  );

  assert(rows.length === source.length, "short pages must not truncate results");
  assert(offsets.join(",") === "0,17,34,51,68,85,102", "offset advances by received row count");
});

Deno.test("readRowsInPages stops at the configured safety cap", async () => {
  const source = Array.from({ length: 20 }, (_, index) => index);
  const rows = await readRowsInPages(
    async (offset, limit) => source.slice(offset, offset + limit),
    { pageSize: 4, maxRows: 9 },
  );

  assert(rows.length === 9, "collection should stop at maxRows");
  assert(rows.at(-1) === 8, "the final capped row should be retained");
});

Deno.test("readRowsInPages returns a short collection on an empty page", async () => {
  const rows = await readRowsInPages(
    async (offset, limit) => offset < 3 ? [offset] : [],
    { pageSize: 10, maxRows: 100 },
  );

  assert(rows.join(",") === "0,1,2", "empty page should end collection");
});

Deno.test("readRowsInPages rejects invalid page options and oversized pages", async () => {
  let invalidMaxRejected = false;
  try {
    await readRowsInPages(async () => [], { maxRows: 0 });
  } catch {
    invalidMaxRejected = true;
  }
  assert(invalidMaxRejected, "zero maxRows should be rejected");

  let oversizedPageRejected = false;
  try {
    await readRowsInPages(async () => [1, 2], { pageSize: 1 });
  } catch {
    oversizedPageRejected = true;
  }
  assert(oversizedPageRejected, "oversized page should be rejected");
});
