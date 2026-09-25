-- ============================================================
-- PaisaPulse — Supabase schema
-- Run this in the Supabase SQL editor (Project → SQL Editor → New query)
-- Mirrors the data shape used by the demo app's mock data layer,
-- so wiring the frontend to real Supabase is a drop-in swap.
-- ============================================================

-- Extensions
create extension if not exists "uuid-ossp";

-- ---------- profiles ----------
-- One row per authenticated user (Supabase Auth handles email/mobile/OTP login).
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  avatar_initial text generated always as (upper(left(full_name, 1))) stored,
  mobile text,
  created_at timestamptz not null default now()
);

-- ---------- categories ----------
-- Shared lookup table; seed with the defaults below, users can add their own later.
create table if not exists public.categories (
  id text primary key,               -- e.g. 'food', 'salary'
  name text not null,
  icon text not null,                -- emoji, matches the app's icon set
  color text not null,               -- hex, used for charts/legends
  type text not null check (type in ('income','expense')),
  owner_id uuid references public.profiles(id) on delete cascade  -- null = global default category
);

-- ---------- transactions ----------
create table if not exists public.transactions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  category_id text not null references public.categories(id),
  type text not null check (type in ('income','expense')),
  amount numeric(12,2) not null check (amount > 0),
  merchant text not null,
  note text default '',
  occurred_on date not null default current_date,
  created_at timestamptz not null default now()
);
create index if not exists idx_transactions_user_date on public.transactions(user_id, occurred_on desc);
create index if not exists idx_transactions_user_category on public.transactions(user_id, category_id);

-- ---------- budgets ----------
create table if not exists public.budgets (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  category_id text not null references public.categories(id),
  monthly_limit numeric(12,2) not null check (monthly_limit > 0),
  created_at timestamptz not null default now(),
  unique(user_id, category_id)
);

-- ---------- pairing_codes ----------
-- Backs the web app's QR-login flow. The web client inserts a fresh
-- row (anonymously) and shows `code` as a QR code, then listens on
-- Realtime for this row's `user_id` to be set. The mobile app, once
-- it has scanned the code, should NOT write user_id directly with
-- the anon key — instead call a Supabase Edge Function (service-role
-- key, server-side only) that validates the code, confirms the
-- scanning user's session, and sets user_id + claimed_at. That
-- indirection is what makes the pairing safe: the anon key alone
-- can never mint a session for someone else.
create table if not exists public.pairing_codes (
  code text primary key,
  user_id uuid references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  expires_at timestamptz not null default (now() + interval '5 minutes')
);
alter table public.pairing_codes enable row level security;
-- Anyone (including anon, pre-login) can create and watch a pairing code —
-- it carries no data of its own until claimed.
create policy "pairing_codes: anyone can create" on public.pairing_codes
  for insert with check (true);
create policy "pairing_codes: anyone can read" on public.pairing_codes
  for select using (true);
-- Row updates (setting user_id) happen only via the Edge Function using
-- the service-role key, which bypasses RLS by design — no client-side
-- update policy is granted here on purpose.

-- Housekeeping: call periodically (e.g. via pg_cron or an Edge Function)
-- to drop stale, unclaimed pairing codes.
create or replace function public.purge_expired_pairing_codes()
returns void as $$
  delete from public.pairing_codes where expires_at < now() and claimed_at is null;
$$ language sql security definer;

-- ============================================================
-- Row Level Security — every table is per-user
-- ============================================================
alter table public.profiles enable row level security;
alter table public.transactions enable row level security;
alter table public.budgets enable row level security;
alter table public.categories enable row level security;

create policy "profiles: read own" on public.profiles for select using (auth.uid() = id);
create policy "profiles: update own" on public.profiles for update using (auth.uid() = id);
create policy "profiles: insert own" on public.profiles for insert with check (auth.uid() = id);

create policy "transactions: full access to own rows" on public.transactions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "budgets: full access to own rows" on public.budgets
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "categories: read defaults and own" on public.categories
  for select using (owner_id is null or owner_id = auth.uid());
create policy "categories: manage own" on public.categories
  for insert with check (owner_id = auth.uid());
create policy "categories: update own" on public.categories
  for update using (owner_id = auth.uid());

-- ============================================================
-- Seed default categories (global, owner_id null)
-- ============================================================
insert into public.categories (id, name, icon, color, type, owner_id) values
  ('food',      'Food & dining',        '🍔', '#e2984a', 'expense', null),
  ('groceries', 'Groceries',            '🛒', '#7aa66b', 'expense', null),
  ('transport', 'Transport',            '🚕', '#4d8fac', 'expense', null),
  ('bills',     'Bills & utilities',    '💡', '#c0503f', 'expense', null),
  ('shopping',  'Shopping',             '🛍️', '#8a5fc2', 'expense', null),
  ('entertain', 'Entertainment',        '🎬', '#c2568f', 'expense', null),
  ('health',    'Health',               '💊', '#3f9c8c', 'expense', null),
  ('rent',      'Rent & housing',       '🏠', '#6b5b3e', 'expense', null),
  ('travel',    'Travel',               '✈️', '#3a7bd5', 'expense', null),
  ('other',     'Other',                '🔖', '#8a8f98', 'expense', null),
  ('salary',    'Salary',               '💰', '#1f8f7e', 'income',  null),
  ('freelance', 'Freelance',            '💻', '#1f8f7e', 'income',  null)
on conflict (id) do nothing;

-- ============================================================
-- Auto-create a profile row whenever a new auth user signs up
-- ============================================================
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, mobile)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)), new.phone);
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
