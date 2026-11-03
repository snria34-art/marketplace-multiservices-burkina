revoke all on function public.open_return(uuid,uuid,text) from public,anon;
grant execute on function public.open_return(uuid,uuid,text) to authenticated;