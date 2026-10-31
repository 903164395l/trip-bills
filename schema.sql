-- Run once in Supabase: SQL Editor -> New query -> paste -> Run.

create table sessions (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(name) between 1 and 40),
  people int not null default 2 check (people between 1 and 50),
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
  created_at timestamptz not null default now()
);

create index on payers (session_id);
create index on bills (session_id);

-- At most 2 sessions can exist at the same time.
create function enforce_max_sessions() returns trigger language plpgsql as $$
begin
  if (select count(*) from sessions) >= 2 then
    raise exception '最多只能同時有 2 個行程，請先刪除一個。';
  end if;
  return new;
end $$;

create trigger max_sessions before insert on sessions
  for each row execute function enforce_max_sessions();

-- No login: anyone who has the page link can read and write.
grant select, insert, update, delete on sessions, payers, bills to anon;

alter table sessions enable row level security;
alter table payers enable row level security;
alter table bills enable row level security;

create policy "link access" on sessions for all to anon using (true) with check (true);
create policy "link access" on payers for all to anon using (true) with check (true);
create policy "link access" on bills for all to anon using (true) with check (true);
