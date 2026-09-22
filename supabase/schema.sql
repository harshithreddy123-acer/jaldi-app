-- Jaldi backend foundation.
-- Run in the Supabase SQL editor or with `supabase db push`.
create extension if not exists postgis with schema extensions;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  avatar_url text,
  role text not null default 'customer' check (role in ('customer', 'provider', 'admin')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Extended profile attributes (Location, Emergency SOS contacts, Vehicle details)
alter table public.profiles add column if not exists age integer;
alter table public.profiles add column if not exists city text;
alter table public.profiles add column if not exists address text;
alter table public.profiles add column if not exists emergency_contact_name text;
alter table public.profiles add column if not exists emergency_contact_phone text;
alter table public.profiles add column if not exists blood_group text;
alter table public.profiles add column if not exists vehicle_model text;
alter table public.profiles add column if not exists vehicle_number text;

create table if not exists public.provider_profiles (
  id uuid primary key references public.profiles(id) on delete cascade,
  bio text,
  verification_status text not null default 'pending'
    check (verification_status in ('pending', 'approved', 'rejected', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Operational provider details are kept separate so the provider can update
-- availability without changing verification data.
create table if not exists public.provider_details (
  user_id uuid primary key references public.provider_profiles(id) on delete cascade,
  vehicle_type text,
  specialties text[] not null default '{}',
  is_online boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.provider_locations (
  provider_id uuid primary key references public.provider_profiles(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  location extensions.geography(point, 4326)
    generated always as (extensions.st_setsrid(extensions.st_makepoint(longitude, latitude), 4326)::extensions.geography) stored,
  recorded_at timestamptz not null default now()
);

create table if not exists public.service_requests (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id),
  provider_id uuid references public.provider_profiles(id),
  service_type text not null check (length(trim(service_type)) > 0),
  description text,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  location extensions.geography(point, 4326)
    generated always as (extensions.st_setsrid(extensions.st_makepoint(longitude, latitude), 4326)::extensions.geography) stored,
  status text not null default 'searching'
    check (status in ('searching', 'assigned', 'accepted', 'in_progress', 'completed', 'cancelled')),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz
);

create table if not exists public.assignments (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.service_requests(id) on delete cascade,
  provider_id uuid not null references public.provider_profiles(id),
  status text not null default 'offered'
    check (status in ('offered', 'accepted', 'declined', 'expired', 'cancelled')),
  offered_at timestamptz not null default now(),
  responded_at timestamptz,
  unique (request_id, provider_id)
);

create table if not exists public.provider_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  vehicle_type text not null,
  specialties text not null,
  notes text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'withdrawn')),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.emergency_events (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id) on delete cascade,
  request_id uuid references public.service_requests(id) on delete set null,
  severity text not null default 'critical' check (severity in ('low', 'medium', 'high', 'critical')),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  location extensions.geography(point, 4326)
    generated always as (extensions.st_setsrid(extensions.st_makepoint(longitude, latitude), 4326)::extensions.geography) stored,
  status text not null default 'active' check (status in ('active', 'open', 'acknowledged', 'resolved', 'cancelled')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.service_requests(id) on delete cascade,
  customer_id uuid not null references public.profiles(id),
  provider_id uuid not null references public.provider_profiles(id),
  score smallint not null check (score between 1 and 5),
  comment text,
  created_at timestamptz not null default now()
);

create index if not exists provider_locations_location_gist on public.provider_locations using gist (location);
create index if not exists service_requests_location_gist on public.service_requests using gist (location);
create index if not exists emergency_events_location_gist on public.emergency_events using gist (location);
create index if not exists service_requests_customer_status on public.service_requests (customer_id, status, created_at desc);
create index if not exists service_requests_provider_status on public.service_requests (provider_id, status);
create index if not exists assignments_provider_status on public.assignments (provider_id, status);
create index if not exists applications_status on public.provider_applications (status, created_at desc);

-- Keep profile rows in sync with Supabase Auth. This function never exposes
-- auth metadata to the client and is safe to run as a trigger.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''),
          new.raw_user_meta_data->>'phone')
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Atomically offer a request to an approved, online provider.
create or replace function public.assign_request(p_request_id uuid, p_provider_id uuid)
returns public.assignments
language plpgsql security definer set search_path = public
as $$
declare result public.assignments;
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles where id = auth.uid() and role in ('admin', 'provider')
  ) then raise exception 'not authorized'; end if;
  if not exists (select 1 from public.provider_details where user_id = p_provider_id and is_online)
    then raise exception 'provider is not online'; end if;
  insert into public.assignments (request_id, provider_id)
  select p_request_id, p_provider_id
  where exists (select 1 from public.service_requests where id = p_request_id and status = 'searching')
  on conflict (request_id, provider_id) do nothing
  returning * into result;
  if result.id is null then raise exception 'request is no longer available'; end if;
  update public.service_requests set status = 'assigned', provider_id = p_provider_id
  where id = p_request_id and status = 'searching';
  return result;
end;
$$;

-- Provider-only, race-safe acceptance. The request update predicate prevents
-- two providers from accepting the same request.
create or replace function public.accept_request(p_request_id uuid)
returns public.service_requests
language plpgsql security definer set search_path = public
as $$
declare result public.service_requests;
begin
  if auth.uid() is null or not exists (
    select 1 from public.provider_profiles where id = auth.uid()
  ) then raise exception 'not authorized'; end if;
  update public.service_requests
  set provider_id = auth.uid(), status = 'accepted', accepted_at = now()
  where id = p_request_id and status in ('searching', 'assigned')
    and (provider_id is null or provider_id = auth.uid())
  returning * into result;
  if result.id is null then raise exception 'request is no longer available'; end if;
  update public.assignments set status = 'accepted', responded_at = now()
  where request_id = p_request_id and provider_id = auth.uid();
  return result;
end;
$$;

alter table public.profiles enable row level security;
alter table public.provider_profiles enable row level security;
alter table public.provider_details enable row level security;
alter table public.provider_locations enable row level security;
alter table public.service_requests enable row level security;
alter table public.assignments enable row level security;
alter table public.provider_applications enable row level security;
alter table public.emergency_events enable row level security;
alter table public.ratings enable row level security;

drop policy if exists "profiles readable by signed in users" on public.profiles;
create policy "profiles readable by signed in users" on public.profiles for select to authenticated using (true);

drop policy if exists "users update own profile" on public.profiles;
create policy "users update own profile" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "providers visible when approved" on public.provider_profiles;
create policy "providers visible when approved" on public.provider_profiles for select to authenticated using (verification_status = 'approved' or id = auth.uid());

drop policy if exists "providers manage own profile" on public.provider_profiles;
create policy "providers manage own profile" on public.provider_profiles for all to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "providers manage own details" on public.provider_details;
create policy "providers manage own details" on public.provider_details for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "providers manage own location" on public.provider_locations;
create policy "providers manage own location" on public.provider_locations for all to authenticated using (provider_id = auth.uid()) with check (provider_id = auth.uid());

drop policy if exists "provider locations readable by authenticated" on public.provider_locations;
create policy "provider locations readable by authenticated" on public.provider_locations for select to authenticated using (true);

drop policy if exists "customers create requests" on public.service_requests;
create policy "customers create requests" on public.service_requests for insert to authenticated with check (customer_id = auth.uid());

drop policy if exists "request parties read requests" on public.service_requests;
create policy "request parties read requests" on public.service_requests for select to authenticated using (customer_id = auth.uid() or provider_id = auth.uid() or status in ('searching', 'assigned'));

drop policy if exists "customers cancel requests" on public.service_requests;
create policy "customers cancel requests" on public.service_requests for update to authenticated using (customer_id = auth.uid()) with check (customer_id = auth.uid());

drop policy if exists "providers update assigned requests" on public.service_requests;
create policy "providers update assigned requests" on public.service_requests
  for update to authenticated
  using (provider_id = auth.uid() or (provider_id is null and status = 'searching'))
  with check (provider_id = auth.uid());

drop policy if exists "assignment parties read" on public.assignments;
create policy "assignment parties read" on public.assignments for select to authenticated using (provider_id = auth.uid() or exists (select 1 from public.service_requests r where r.id = request_id and r.customer_id = auth.uid()));

drop policy if exists "users manage own application" on public.provider_applications;
create policy "users manage own application" on public.provider_applications for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "users manage own emergencies" on public.emergency_events;
create policy "users manage own emergencies" on public.emergency_events for all to authenticated using (customer_id = auth.uid()) with check (customer_id = auth.uid());

drop policy if exists "participants read ratings" on public.ratings;
create policy "participants read ratings" on public.ratings for select to authenticated using (customer_id = auth.uid() or provider_id = auth.uid());

drop policy if exists "customers create ratings" on public.ratings;
create policy "customers create ratings" on public.ratings for insert to authenticated with check (customer_id = auth.uid());

grant execute on function public.assign_request(uuid, uuid) to authenticated;
grant execute on function public.accept_request(uuid) to authenticated;

-- Enable Realtime WebSockets safely if not already added
do $$
begin
  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'provider_locations'
  ) then
    alter publication supabase_realtime add table public.provider_locations;
  end if;
  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'service_requests'
  ) then
    alter publication supabase_realtime add table public.service_requests;
  end if;
end;
$$;

-- Helper function to approve a provider application by User Email or ID
create or replace function public.approve_provider_application(p_user_email text)
returns text language plpgsql security definer as $$
declare
  v_user_id uuid;
  v_vehicle text;
  v_spec text;
begin
  select u.id into v_user_id
  from auth.users u where u.email = p_user_email;

  if v_user_id is null then
    return 'User with email ' || p_user_email || ' not found in auth.users.';
  end if;

  select vehicle_type, specialties into v_vehicle, v_spec
  from public.provider_applications
  where user_id = v_user_id
  order by created_at desc limit 1;

  update public.provider_applications
  set status = 'approved', reviewed_at = now()
  where user_id = v_user_id;

  update public.profiles
  set role = 'provider'
  where id = v_user_id;

  insert into public.provider_profiles (id, verification_status, bio)
  values (v_user_id, 'approved', coalesce(v_spec, 'Certified Highway Technician'))
  on conflict (id) do update set verification_status = 'approved';

  insert into public.provider_details (user_id, vehicle_type, is_online)
  values (v_user_id, coalesce(v_vehicle, 'Mobile Service Van'), true)
  on conflict (user_id) do update
  set vehicle_type = coalesce(v_vehicle, public.provider_details.vehicle_type),
      is_online = true;

  return 'Successfully approved ' || p_user_email || ' as verified technician.';
end;
$$;

grant execute on function public.approve_provider_application(text) to authenticated, service_role;

-- 1-Click self approval function for development / MVP testing
create or replace function public.self_approve_technician()
returns text language plpgsql security definer as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  update public.profiles set role = 'provider' where id = auth.uid();

  insert into public.provider_profiles (id, verification_status, bio)
  values (auth.uid(), 'approved', 'Certified Highway Technician')
  on conflict (id) do update set verification_status = 'approved';

  insert into public.provider_details (user_id, vehicle_type, is_online)
  values (auth.uid(), 'Mobile Service Van', true)
  on conflict (user_id) do update set is_online = true;

  return 'Account successfully upgraded to certified technician.';
end;
$$;

grant execute on function public.self_approve_technician() to authenticated, service_role;

-- Device Push Notification Token
alter table public.profiles add column if not exists fcm_token text;

-- Storage Bucket for Provider Documents (KYC, Driver License, Certifications)
insert into storage.buckets (id, name, public)
values ('provider-documents', 'provider-documents', false)
on conflict (id) do nothing;

drop policy if exists "Authenticated users can upload provider documents" on storage.objects;
create policy "Authenticated users can upload provider documents"
on storage.objects for insert to authenticated
with check (bucket_id = 'provider-documents');

drop policy if exists "Users can view their own provider documents" on storage.objects;
create policy "Users can view their own provider documents"
on storage.objects for select to authenticated
using (
  bucket_id = 'provider-documents'
  and (auth.uid()::text = (storage.foldername(name))[1] or exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  ))
);

-- Geospatial matching: Find nearest online & verified technicians within a radius (default 25km)
drop function if exists public.find_nearest_technicians(double precision, double precision, double precision);
drop function if exists public.find_nearest_technicians(double precision, double precision);

create or replace function public.find_nearest_technicians(
  p_lat double precision,
  p_lng double precision,
  p_radius_meters double precision default 25000
)
returns table (
  provider_id uuid,
  full_name text,
  phone text,
  vehicle_type text,
  specialties text[],
  distance_meters double precision,
  latitude double precision,
  longitude double precision,
  fcm_token text
)
language sql security definer set search_path = public, extensions as $$
  select 
    pl.provider_id,
    p.full_name,
    p.phone,
    pd.vehicle_type,
    pd.specialties,
    extensions.st_distance(
      pl.location,
      extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography
    ) as distance_meters,
    pl.latitude,
    pl.longitude,
    p.fcm_token
  from public.provider_locations pl
  join public.provider_profiles pp on pp.id = pl.provider_id
  join public.provider_details pd on pd.user_id = pl.provider_id
  join public.profiles p on p.id = pl.provider_id
  where pp.verification_status = 'approved'
    and pd.is_online = true
    and extensions.st_dwithin(
      pl.location,
      extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography,
      p_radius_meters
    )
  order by distance_meters asc;
$$;

grant execute on function public.find_nearest_technicians(double precision, double precision, double precision) to authenticated;
