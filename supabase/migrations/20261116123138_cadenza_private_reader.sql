-- App-specific authorization only. Existing PRONOTE tables/jobs are unchanged.
create schema if not exists cadenza_private;
revoke all on schema cadenza_private from public, anon, authenticated, service_role;
create table if not exists cadenza_private.reader_access (
  email_sha256 text primary key check (email_sha256 ~ '^[a-f0-9]{64}$'),
  user_id uuid unique references auth.users(id) on delete set null,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);
alter table cadenza_private.reader_access enable row level security;
revoke all on cadenza_private.reader_access from public, anon, authenticated, service_role;
comment on table cadenza_private.reader_access is
  'Admin-managed Cadenza reader allowlist. Seed the intended verified account privately, never in the public repository.';
