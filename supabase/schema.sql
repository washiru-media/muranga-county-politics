-- Murang'a County Politics: Supabase schema
-- Run this entire file in Supabase SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.poll_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  area text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create unique index if not exists poll_categories_name_area_unique
on public.poll_categories (lower(name), lower(coalesce(area,'')));

create table if not exists public.aspirants (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.poll_categories(id) on delete cascade,
  name text not null,
  photo_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists aspirants_category_idx on public.aspirants(category_id);

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- IP hashes are created only by the Vercel server endpoint; raw IP addresses are never stored.
create table if not exists public.ip_vote_locks (
  id bigint generated always as identity primary key,
  category_id uuid not null references public.poll_categories(id) on delete cascade,
  ip_hash text not null,
  created_at timestamptz not null default now(),
  unique(category_id, ip_hash)
);

create table if not exists public.votes (
  id bigint generated always as identity primary key,
  category_id uuid not null references public.poll_categories(id) on delete cascade,
  aspirant_id uuid not null references public.aspirants(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists votes_category_idx on public.votes(category_id);

create or replace function public.is_poll_admin()
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists(select 1 from public.admin_users where user_id = auth.uid());
$$;

alter table public.poll_categories enable row level security;
alter table public.aspirants enable row level security;
alter table public.admin_users enable row level security;
alter table public.ip_vote_locks enable row level security;
alter table public.votes enable row level security;

drop policy if exists "Public can read active categories" on public.poll_categories;
create policy "Public can read active categories" on public.poll_categories
for select to anon, authenticated using (is_active = true or public.is_poll_admin());

drop policy if exists "Admins manage categories" on public.poll_categories;
create policy "Admins manage categories" on public.poll_categories
for all to authenticated using (public.is_poll_admin()) with check (public.is_poll_admin());

drop policy if exists "Public can read active aspirants" on public.aspirants;
create policy "Public can read active aspirants" on public.aspirants
for select to anon, authenticated using (is_active = true or public.is_poll_admin());

drop policy if exists "Admins manage aspirants" on public.aspirants;
create policy "Admins manage aspirants" on public.aspirants
for all to authenticated using (public.is_poll_admin()) with check (public.is_poll_admin());

drop policy if exists "Admins can read admin list" on public.admin_users;
create policy "Admins can read admin list" on public.admin_users
for select to authenticated using (public.is_poll_admin());

-- No client-side direct inserts/reads/updates for votes or IP locks.
drop policy if exists "No direct public vote access" on public.votes;
drop policy if exists "No direct public IP lock access" on public.ip_vote_locks;

create or replace function public.cast_poll_vote(p_category_id uuid, p_aspirant_id uuid, p_ip_hash text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_ip_hash is null or length(p_ip_hash) < 32 then
    raise exception 'Invalid voter fingerprint';
  end if;
  if not exists (
    select 1 from public.aspirants
    where id = p_aspirant_id and category_id = p_category_id and is_active = true
  ) then
    raise exception 'This aspirant is not available in the selected category';
  end if;

  insert into public.ip_vote_locks(category_id, ip_hash)
  values (p_category_id, p_ip_hash);

  insert into public.votes(category_id, aspirant_id)
  values (p_category_id, p_aspirant_id);
exception
  when unique_violation then
    raise exception 'A vote has already been submitted from this IP address for this category';
end;
$$;

create or replace function public.get_poll_results(p_category_id uuid)
returns table(aspirant_id uuid, aspirant_name text, photo_url text, vote_count bigint)
language sql stable security definer
set search_path = public
as $$
  select a.id, a.name, a.photo_url, count(v.id)::bigint
  from public.aspirants a
  left join public.votes v on v.aspirant_id = a.id and v.category_id = a.category_id
  where a.category_id = p_category_id and a.is_active = true
  group by a.id, a.name, a.photo_url
  order by count(v.id) desc, a.name asc;
$$;

revoke all on function public.cast_poll_vote(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.cast_poll_vote(uuid,uuid,text) to service_role;
revoke all on function public.get_poll_results(uuid) from public;
grant execute on function public.get_poll_results(uuid) to anon, authenticated;

-- Storage bucket for small aspirant profile images.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('aspirant-photos','aspirant-photos',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 5242880,
allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "Public can view aspirant photos" on storage.objects;
create policy "Public can view aspirant photos" on storage.objects
for select to anon, authenticated using (bucket_id = 'aspirant-photos');

drop policy if exists "Admins upload aspirant photos" on storage.objects;
create policy "Admins upload aspirant photos" on storage.objects
for insert to authenticated with check (bucket_id = 'aspirant-photos' and public.is_poll_admin());

drop policy if exists "Admins update aspirant photos" on storage.objects;
create policy "Admins update aspirant photos" on storage.objects
for update to authenticated using (bucket_id = 'aspirant-photos' and public.is_poll_admin())
with check (bucket_id = 'aspirant-photos' and public.is_poll_admin());

drop policy if exists "Admins delete aspirant photos" on storage.objects;
create policy "Admins delete aspirant photos" on storage.objects
for delete to authenticated using (bucket_id = 'aspirant-photos' and public.is_poll_admin());
