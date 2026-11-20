-- REVIEW PATCH ONLY. Do not run directly in production.
-- Number this with supabase migration new, test against an isolated PostgreSQL
-- database, and deploy only after the Flutter/SQL CI checks pass.

begin;

-- Mechanic profiles become explicit about what they can repair and when they
-- accept a call. All hours are Burkina local time, not a device-supplied clock.

alter table public.mechanics
  add column if not exists service_open_time time not null default time '08:00',
  add column if not exists service_close_time time not null default time '20:00',
  add column if not exists service_days smallint[] not null default array[1,2,3,4,5,6]::smallint[],
  add column if not exists service_timezone text not null default 'Africa/Ouagadougou';

alter table public.mechanics
  drop constraint if exists mechanics_service_hours_valid;
alter table public.mechanics
  add constraint mechanics_service_hours_valid
  check (
    service_open_time < service_close_time
    and cardinality(service_days) between 1 and 7
    and service_days <@ array[1,2,3,4,5,6,7]::smallint[]
    and service_timezone = 'Africa/Ouagadougou'
  );

alter table public.mechanic_services
  drop constraint if exists mechanic_services_vehicle_type_check;
alter table public.mechanic_services
  add constraint mechanic_services_vehicle_type_check
  check (vehicle_type in (
    'CAR','ELECTRIC_CAR','MOTORCYCLE','ELECTRIC_MOTORCYCLE',
    'BICYCLE','ELECTRIC_BICYCLE','TRUCK'
  ));

alter table public.mechanic_requests
  drop constraint if exists mechanic_requests_vehicle_type_check;
alter table public.mechanic_requests
  add constraint mechanic_requests_vehicle_type_check
  check (vehicle_type in (
    'CAR','ELECTRIC_CAR','MOTORCYCLE','ELECTRIC_MOTORCYCLE',
    'BICYCLE','ELECTRIC_BICYCLE','TRUCK'
  ));

alter table public.mechanic_requests
  add column if not exists requested_service_type text not null default 'GENERAL_REPAIR',
  add column if not exists service_location_type text not null default 'ROADSIDE',
  add column if not exists vehicle_subtype text,
  add column if not exists location_note text,
  add column if not exists requested_for timestamptz;

alter table public.mechanic_requests
  drop constraint if exists mechanic_requests_service_location_type_valid;
alter table public.mechanic_requests
  add constraint mechanic_requests_service_location_type_valid
  check (service_location_type in ('HOME','OFFICE','ROADSIDE'));

create table if not exists public.mechanic_capabilities (
  id uuid primary key default gen_random_uuid(),
  mechanic_id uuid not null references public.mechanics(id) on delete cascade,
  vehicle_type text not null check (vehicle_type in (
    'CAR','ELECTRIC_CAR','MOTORCYCLE','ELECTRIC_MOTORCYCLE',
    'BICYCLE','ELECTRIC_BICYCLE','TRUCK'
  )),
  service_type text not null default 'GENERAL_REPAIR'
    check (length(trim(service_type)) between 2 and 80),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(mechanic_id,vehicle_type,service_type)
);

create table if not exists public.mechanic_service_rates (
  id uuid primary key default gen_random_uuid(),
  mechanic_id uuid not null references public.mechanics(id) on delete cascade,
  vehicle_type text not null check (vehicle_type in (
    'CAR','ELECTRIC_CAR','MOTORCYCLE','ELECTRIC_MOTORCYCLE',
    'BICYCLE','ELECTRIC_BICYCLE','TRUCK'
  )),
  service_location_type text not null
    check (service_location_type in ('HOME','OFFICE','ROADSIDE')),
  base_price numeric(14,2) not null check (base_price >= 0),
  currency text not null default 'XOF' check (currency='XOF'),
  adjustment_note text,
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  unique(mechanic_id,vehicle_type,service_location_type)
);

create index if not exists idx_mechanic_capabilities_type_active
  on public.mechanic_capabilities(vehicle_type,active,mechanic_id);
create index if not exists idx_mechanic_rates_lookup
  on public.mechanic_service_rates(vehicle_type,service_location_type,active,mechanic_id);

alter table public.mechanic_capabilities enable row level security;
alter table public.mechanic_service_rates enable row level security;
revoke all on public.mechanic_capabilities from anon,authenticated;
revoke all on public.mechanic_service_rates from anon,authenticated;

create or replace function public.mechanic_is_open(
  p_mechanic_id uuid,
  p_at timestamptz default now()
) returns boolean
language sql stable security definer
set search_path = pg_catalog, public
as $function$
  select exists (
    select 1
    from public.mechanics m
    where m.id=p_mechanic_id
      and m.active=true
      and m.verification_status='VERIFIED'
      and extract(isodow from (p_at at time zone m.service_timezone))::smallint = any(m.service_days)
      and (p_at at time zone m.service_timezone)::time >= m.service_open_time
      and (p_at at time zone m.service_timezone)::time < m.service_close_time
      and not exists (
        select 1 from public.mechanic_time_off t
        where t.mechanic_id=m.id and t.starts_at<=p_at and t.ends_at>p_at
      )
  );
$function$;

create or replace function public.save_mechanic_service_profile(
  p_vehicle_types text[],
  p_service_types text[],
  p_open_time time,
  p_close_time time,
  p_service_days smallint[],
  p_home_price numeric,
  p_office_price numeric,
  p_roadside_price numeric,
  p_adjustment_note text default null
) returns boolean
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user uuid := (select auth.uid());
  v_mechanic uuid;
  v_vehicle text;
  v_service text;
  v_type text;
  v_price numeric;
  v_days smallint[] := coalesce(p_service_days,array[]::smallint[]);
begin
  perform private.require_active_account();
  if v_user is null then raise exception 'not_authenticated'; end if;

  select id into v_mechanic
  from public.mechanics
  where user_id=v_user and active=true
  for update;

  if v_mechanic is null then raise exception 'mechanic_profile_not_found'; end if;

  if p_vehicle_types is null or cardinality(p_vehicle_types)=0
     or cardinality(p_vehicle_types)>7
     or cardinality(p_vehicle_types) <> (
       select count(distinct x) from unnest(p_vehicle_types) x
     )
     or exists (
       select 1 from unnest(p_vehicle_types) x
       where x not in (
         'CAR','ELECTRIC_CAR','MOTORCYCLE','ELECTRIC_MOTORCYCLE',
         'BICYCLE','ELECTRIC_BICYCLE','TRUCK'
       )
     ) then
    raise exception 'mechanic_vehicle_capabilities_invalid';
  end if;

  if p_service_types is null or cardinality(p_service_types)=0
     or cardinality(p_service_types)>30
     or cardinality(p_service_types) <> (
       select count(distinct upper(trim(x))) from unnest(p_service_types) x
     )
     or exists (
       select 1 from unnest(p_service_types) x
       where length(trim(x))<2 or length(trim(x))>80
     ) then
    raise exception 'mechanic_service_types_invalid';
  end if;

  if p_open_time is null or p_close_time is null or p_open_time>=p_close_time then
    raise exception 'mechanic_service_hours_invalid';
  end if;

  if cardinality(v_days)=0 or cardinality(v_days)>7
     or not (v_days <@ array[1,2,3,4,5,6,7]::smallint[]) then
    raise exception 'mechanic_service_days_invalid';
  end if;

  if p_home_price is null or p_home_price<0
     or p_office_price is null or p_office_price<0
     or p_roadside_price is null or p_roadside_price<0 then
    raise exception 'mechanic_service_price_invalid';
  end if;

  update public.mechanics
  set service_open_time=p_open_time,
      service_close_time=p_close_time,
      service_days=v_days,
      service_timezone='Africa/Ouagadougou'
  where id=v_mechanic;

  update public.mechanic_capabilities
  set active=false
  where mechanic_id=v_mechanic
    and (
      vehicle_type <> all(p_vehicle_types)
      or service_type <> all(array(
        select upper(trim(x)) from unnest(p_service_types) x
      ))
    );

  update public.mechanic_service_rates
  set active=false,updated_at=now()
  where mechanic_id=v_mechanic
    and vehicle_type <> all(p_vehicle_types);

  foreach v_vehicle in array p_vehicle_types loop
    foreach v_service in array p_service_types loop
      insert into public.mechanic_capabilities(
        mechanic_id,vehicle_type,service_type,active
      ) values (
        v_mechanic,v_vehicle,upper(trim(v_service)),true
      )
      on conflict (mechanic_id,vehicle_type,service_type)
      do update set active=true;
    end loop;

    foreach v_type in array array['HOME','OFFICE','ROADSIDE']::text[] loop
      v_price := case v_type
        when 'HOME' then p_home_price
        when 'OFFICE' then p_office_price
        else p_roadside_price
      end;

      insert into public.mechanic_service_rates(
        mechanic_id,vehicle_type,service_location_type,base_price,
        adjustment_note,active,updated_at
      ) values (
        v_mechanic,v_vehicle,v_type,v_price,
        nullif(trim(coalesce(p_adjustment_note,'')),''),true,now()
      )
      on conflict (mechanic_id,vehicle_type,service_location_type)
      do update set base_price=excluded.base_price,
        adjustment_note=excluded.adjustment_note,
        active=true,updated_at=now();
    end loop;
  end loop;

  return true;
end;
$function$;

create or replace function public.get_public_mechanics_v2()
returns table (
  id uuid,
  display_name text,
  service_radius_km numeric,
  availability_status text,
  availability_starts_at timestamptz,
  availability_ends_at timestamptz,
  service_open_time text,
  service_close_time text,
  service_days smallint[],
  services jsonb
)
language sql stable security definer
set search_path = pg_catalog, public
as $function$
  select
    m.id,
    m.display_name,
    m.service_radius_km,
    coalesce(a.status,'UNAVAILABLE') as availability_status,
    a.starts_at as availability_starts_at,
    a.ends_at as availability_ends_at,
    to_char(m.service_open_time,'HH24:MI') as service_open_time,
    to_char(m.service_close_time,'HH24:MI') as service_close_time,
    m.service_days,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'vehicle_type',cap.vehicle_type,
        'service_type',cap.service_type,
        'rates',coalesce((
          select jsonb_agg(jsonb_build_object(
            'service_location_type',r.service_location_type,
            'base_price',r.base_price,
            'currency',r.currency,
            'adjustment_note',r.adjustment_note
          ) order by r.service_location_type)
          from public.mechanic_service_rates r
          where r.mechanic_id=m.id
            and r.vehicle_type=cap.vehicle_type
            and r.active=true
        ),'[]'::jsonb)
      ) order by cap.vehicle_type)
      from public.mechanic_capabilities cap
      where cap.mechanic_id=m.id and cap.active=true
    ),'[]'::jsonb) as services
  from public.mechanics m
  left join lateral (
    select ma.status,ma.starts_at,ma.ends_at
    from public.mechanic_availability ma
    where ma.mechanic_id=m.id
      and ma.starts_at<=now()
      and (ma.ends_at is null or ma.ends_at>now())
    order by ma.starts_at desc,ma.id desc
    limit 1
  ) a on true
  where m.active=true
    and m.verification_status='VERIFIED'
    and public.mechanic_is_open(m.id,now())
    and coalesce(a.status,'UNAVAILABLE') <> 'UNAVAILABLE'
  order by m.display_name
  limit 100;
$function$;

create or replace function public.create_mechanic_request_v2(
  p_vehicle_type text,
  p_service_location_type text,
  p_service_type text,
  p_problem_type text,
  p_description text default null,
  p_location_note text default null,
  p_latitude double precision default null,
  p_longitude double precision default null
) returns uuid
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user uuid := (select auth.uid());
  v_vehicle text := upper(trim(coalesce(p_vehicle_type,'')));
  v_location text := upper(trim(coalesce(p_service_location_type,'')));
  v_service text := upper(trim(coalesce(p_service_type,'')));
  v_id uuid;
begin
  perform private.require_active_account();
  if v_user is null then raise exception 'not_authenticated'; end if;

  if v_vehicle not in (
    'CAR','ELECTRIC_CAR','MOTORCYCLE','ELECTRIC_MOTORCYCLE',
    'BICYCLE','ELECTRIC_BICYCLE','TRUCK'
  ) then
    raise exception 'invalid_vehicle_type';
  end if;

  if v_location not in ('HOME','OFFICE','ROADSIDE') then
    raise exception 'invalid_service_location_type';
  end if;

  if length(v_service)<2 or length(v_service)>80 then
    raise exception 'mechanic_service_type_invalid';
  end if;

  if nullif(trim(coalesce(p_problem_type,'')),'') is null
     or length(trim(p_problem_type))>160 then
    raise exception 'problem_required';
  end if;

  if (p_latitude is null or p_longitude is null)
     or p_latitude not between -90 and 90
     or p_longitude not between -180 and 180 then
    raise exception 'valid_coordinates_required';
  end if;

  if v_location in ('HOME','OFFICE')
     and nullif(trim(coalesce(p_location_note,'')),'') is null then
    raise exception 'service_location_details_required';
  end if;

  if not exists (
    select 1
    from public.mechanics m
    join public.mechanic_capabilities c
      on c.mechanic_id=m.id and c.vehicle_type=v_vehicle
        and c.service_type=v_service and c.active=true
    join public.mechanic_service_rates r
      on r.mechanic_id=m.id and r.vehicle_type=v_vehicle
      and r.service_location_type=v_location and r.active=true
    where m.active=true and m.verification_status='VERIFIED'
      and public.mechanic_is_open(m.id,now())
      and exists (
        select 1 from public.mechanic_availability ma
        where ma.mechanic_id=m.id
          and ma.starts_at<=now()
          and (ma.ends_at is null or ma.ends_at>now())
          and ma.status in ('AVAILABLE','IN_10_MIN','IN_20_MIN','IN_30_MIN')
      )
  ) then
    raise exception 'no_compatible_mechanics_available';
  end if;

  insert into public.mechanic_requests(
    customer_id,vehicle_type,problem_type,description,
    latitude,longitude,status,requested_service_type,service_location_type,
    vehicle_subtype,location_note
  ) values (
    v_user,v_vehicle,trim(p_problem_type),
    nullif(trim(coalesce(p_description,'')),''),
    p_latitude,p_longitude,'OPEN',v_service,v_location,
    v_vehicle,nullif(trim(coalesce(p_location_note,'')),'')
  ) returning id into v_id;

  return v_id;
end;
$function$;

revoke all on function public.mechanic_is_open(uuid,timestamptz) from public,anon,authenticated;
revoke all on function public.save_mechanic_service_profile(text[],text[],time without time zone,time without time zone,smallint[],numeric,numeric,numeric,text) from public,anon;
revoke all on function public.get_public_mechanics_v2() from public,anon;
revoke all on function public.create_mechanic_request_v2(text,text,text,text,text,text,double precision,double precision) from public,anon;
grant execute on function public.save_mechanic_service_profile(text[],text[],time without time zone,time without time zone,smallint[],numeric,numeric,numeric,text) to authenticated;
grant execute on function public.get_public_mechanics_v2() to authenticated;
grant execute on function public.create_mechanic_request_v2(text,text,text,text,text,text,double precision,double precision) to authenticated;

commit;
