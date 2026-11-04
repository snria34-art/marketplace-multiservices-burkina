BEGIN;
REVOKE EXECUTE ON FUNCTION public.st_estimatedextent(text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.st_estimatedextent(text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.st_estimatedextent(text, text, text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.st_estimatedextent(text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.st_estimatedextent(text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.st_estimatedextent(text, text, text, boolean) TO service_role;
COMMIT;