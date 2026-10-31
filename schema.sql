-- Run once in Supabase: SQL Editor -> New query -> paste -> Run.

create table sessions (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(name) between 1 and 40),
  people int not null default 2 check (people between 1 and 50),
  code text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{4}$'), -- invite code, also the trip's password
  owner_key text not null check (length(owner_key) >= 20),         -- secret kept on the creator's phone
  created_at timestamptz not null default now()
);

create table payers (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references sessions on delete cascade,
  name text not null check (length(name) between 1 and 30),
  created_at timestamptz not null default now(),
  unique (session_id, name)
);

create table bills (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references sessions on delete cascade,
  payer_id uuid not null references payers on delete cascade,
  description text not null default '' check (length(description) <= 60),
  category text not null check (length(category) between 1 and 20),
  amount numeric(12, 2) not null check (amount > 0 and amount < 10000000),
  spent_on date not null default current_date,
  owner_key text,                                                  -- secret kept on the phone that entered it
  created_at timestamptz not null default now()
);

create index on payers (session_id);
create index on bills (session_id);

-- Trips are private: every request must send the trip's code in the x-trip-code header,
-- and deleting a trip (or changing a bill) also needs the author's phone key in x-owner-key.
-- Helpers live outside the public schema so they are not exposed through the API.
create schema private;
grant usage on schema private to anon;

create function private.header(name text) returns text language sql stable as $$
  select current_setting('request.headers', true)::json ->> name
$$;

create function private.in_trip(sid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from sessions where id = sid and code = private.header('x-trip-code'))
$$;

create function private.owns_trip(sid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from sessions where id = sid
    and code = private.header('x-trip-code') and owner_key = private.header('x-owner-key'))
$$;

create function private.owns_bill(bid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from bills where id = bid and owner_key = private.header('x-owner-key'))
$$;

grant execute on all functions in schema private to anon;

-- owner_key can be written but never read back.
grant select (id, name, people, code, created_at), insert (name, code, owner_key), update (people), delete
  on sessions to anon;
grant select, insert, delete on payers to anon;
grant select (id, session_id, payer_id, description, category, amount, spent_on, created_at),
  insert (id, session_id, payer_id, description, category, amount, spent_on, owner_key),
  update (payer_id, description, category, amount, spent_on), delete
  on bills to anon;

alter table sessions enable row level security;
alter table payers enable row level security;
alter table bills enable row level security;

create policy "members read" on sessions for select to anon using (code = private.header('x-trip-code'));
create policy "anyone creates" on sessions for insert to anon with check (code = private.header('x-trip-code'));
create policy "members edit" on sessions for update to anon using (private.in_trip(id));
create policy "creator deletes" on sessions for delete to anon using (private.owns_trip(id));

create policy "members only" on payers for all to anon
  using (private.in_trip(session_id)) with check (private.in_trip(session_id));
create policy "members read" on bills for select to anon using (private.in_trip(session_id));
create policy "members add" on bills for insert to anon with check (private.in_trip(session_id));
create policy "author edits" on bills for update to anon
  using (private.in_trip(session_id) and private.owns_bill(id)) with check (private.in_trip(session_id));
create policy "author deletes" on bills for delete to anon using (private.in_trip(session_id) and private.owns_bill(id));
