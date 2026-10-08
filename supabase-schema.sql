create extension if not exists pgcrypto with schema extensions;

create table if not exists public.lottery_rooms (
  code text primary key check (code ~ '^[A-Z2-9]{12}$'),
  host_token_hash bytea not null,
  max_members smallint not null check (max_members between 2 and 20),
  status text not null default 'open' check (status in ('open', 'finished')),
  leader_name text,
  deputy_name text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours'
);

create table if not exists public.lottery_participants (
  id bigint generated always as identity primary key,
  room_code text not null references public.lottery_rooms(code) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  joined_at timestamptz not null default now()
);

create unique index if not exists lottery_participants_unique_name
  on public.lottery_participants (room_code, lower(name));

alter table public.lottery_rooms enable row level security;
alter table public.lottery_participants enable row level security;
revoke all on public.lottery_rooms, public.lottery_participants from public, anon, authenticated;

create or replace function public.create_lottery_room(
  p_code text,
  p_host_token text,
  p_max_members integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if p_code is null
    or p_host_token is null
    or p_max_members is null
    or p_code !~ '^[A-Z2-9]{12}$'
    or p_host_token !~ '^[A-Z2-9]{48}$'
    or p_max_members not between 2 and 20 then
    raise exception using message = 'invalid_room_setup';
  end if;

  insert into public.lottery_rooms (code, host_token_hash, max_members)
  values (p_code, extensions.digest(p_host_token, 'sha256'), p_max_members);

  return jsonb_build_object('code', p_code);
end;
$$;

create or replace function public.get_lottery_room(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  room public.lottery_rooms%rowtype;
begin
  select * into room
  from public.lottery_rooms
  where code = upper(p_code);

  if not found or room.expires_at <= now() then
    raise exception using message = 'room_not_found_or_expired';
  end if;

  return jsonb_build_object(
    'code', room.code,
    'status', room.status,
    'max_members', room.max_members,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object('name', participant.name) order by participant.joined_at, participant.id)
      from public.lottery_participants as participant
      where participant.room_code = room.code
    ), '[]'::jsonb),
    'leader_name', room.leader_name,
    'deputy_name', room.deputy_name
  );
end;
$$;

create or replace function public.join_lottery_room(p_code text, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  room public.lottery_rooms%rowtype;
  clean_name text := btrim(p_name);
  member_count integer;
  inserted_count integer;
begin
  if clean_name is null or char_length(clean_name) not between 1 and 40 then
    raise exception using message = 'invalid_name';
  end if;

  select * into room
  from public.lottery_rooms
  where code = upper(p_code)
  for update;

  if not found or room.expires_at <= now() then
    raise exception using message = 'room_not_found_or_expired';
  end if;
  if room.status <> 'open' then
    raise exception using message = 'room_closed';
  end if;

  select count(*) into member_count
  from public.lottery_participants
  where room_code = room.code;

  if member_count >= room.max_members then
    raise exception using message = 'room_full';
  end if;

  insert into public.lottery_participants (room_code, name)
  values (room.code, clean_name)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;

  if inserted_count = 0 then
    raise exception using message = 'duplicate_name';
  end if;

  return jsonb_build_object('joined', true);
end;
$$;

create or replace function public.draw_lottery_room(p_code text, p_host_token text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  room public.lottery_rooms%rowtype;
  leader text;
  deputy text;
  member_count integer;
begin
  select * into room
  from public.lottery_rooms
  where code = upper(p_code)
  for update;

  if not found or room.expires_at <= now() then
    raise exception using message = 'room_not_found_or_expired';
  end if;
  if room.host_token_hash is distinct from extensions.digest(coalesce(p_host_token, ''), 'sha256') then
    raise exception using message = 'invalid_host_token';
  end if;
  if room.status <> 'open' then
    raise exception using message = 'room_closed';
  end if;

  select count(*) into member_count
  from public.lottery_participants
  where room_code = room.code;
  if member_count < 2 then
    raise exception using message = 'not_enough_members';
  end if;

  select name into leader
  from public.lottery_participants
  where room_code = room.code
  order by random()
  limit 1;

  select name into deputy
  from public.lottery_participants
  where room_code = room.code and name <> leader
  order by random()
  limit 1;

  update public.lottery_rooms
  set status = 'finished', leader_name = leader, deputy_name = deputy
  where code = room.code;

  return jsonb_build_object('leader_name', leader, 'deputy_name', deputy);
end;
$$;

revoke all on function public.create_lottery_room(text, text, integer) from public;
revoke all on function public.get_lottery_room(text) from public;
revoke all on function public.join_lottery_room(text, text) from public;
revoke all on function public.draw_lottery_room(text, text) from public;
grant execute on function public.create_lottery_room(text, text, integer) to anon, authenticated;
grant execute on function public.get_lottery_room(text) to anon, authenticated;
grant execute on function public.join_lottery_room(text, text) to anon, authenticated;
grant execute on function public.draw_lottery_room(text, text) to anon, authenticated;
