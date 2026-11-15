export interface ReadRowsInPagesOptions {
  /** Maximum number of rows to collect before reporting a capped result. */
  maxRows?: number;
  /** Requested page size. Keep below the default PostgREST max-rows setting. */
  pageSize?: number;
}

/**
 * Collect rows through range pagination.
 *
 * The fetcher may return fewer rows than requested because the PostgREST
 * max-rows setting can impose a lower cap. Continue from the number actually
 * received rather than assuming a full page, and stop only on an empty page
 * or the explicit safety cap.
 */
export async function readRowsInPages<T>(
  fetchPage: (offset: number, pageSize: number) => Promise<readonly T[]>,
  options: ReadRowsInPagesOptions = {},
): Promise<T[]> {
  const maxRows = options.maxRows ?? 10001;
  const pageSize = options.pageSize ?? 500;

  if (!Number.isSafeInteger(maxRows) || maxRows <= 0) {
    throw new RangeError("maxRows must be a positive safe integer");
  }
  if (!Number.isSafeInteger(pageSize) || pageSize <= 0) {
    throw new RangeError("pageSize must be a positive safe integer");
  }

  const rows: T[] = [];
  while (rows.length < maxRows) {
    const requested = Math.min(pageSize, maxRows - rows.length);
    const page = await fetchPage(rows.length, requested);
    if (!Array.isArray(page)) {
      throw new TypeError("fetchPage must return an array");
    }
    if (page.length > requested) {
      throw new RangeError("fetchPage returned more rows than requested");
    }
    if (page.length === 0) break;
    rows.push(...page);
  }

  return rows;
}
