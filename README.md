# PaisaPulse — Expense Tracker

A simple, mobile-first expense tracker: sign in with email, mobile, or QR, then
track spending, income, budgets, and trends.

**What's in this folder**
- `index.html` — the whole frontend (HTML/CSS/JS, no build step). Right now it
  runs on seeded sample data stored in the browser's `localStorage`, so you can
  open it and use it immediately with no backend.
- `supabase-schema.sql` — the real database schema (`profiles`, `categories`,
  `transactions`, `budgets`, `pairing_codes`), with row-level security so
  each user only ever sees their own data.
- `config.example.js` — template for your Supabase URL/key. Copy to
  `config.js` (git-ignored) to actually connect the app to Supabase.
- `.github/workflows/deploy.yml` — builds `config.js` from GitHub repo
  secrets and deploys to GitHub Pages on every push to `main`.
- This README — how to wire it all together, including **Secrets setup**.

## 1. Try it now
Just open `index.html` in a browser. Any email/password, any mobile number, or
"Simulate scan" on the QR tab will log you in. Data (transactions, budgets,
theme) is seeded on first load and persists per-browser via `localStorage`.

## 2. Set up Supabase (real backend)
`index.html` already contains the Supabase wiring — email/password login,
mobile OTP (send + verify), a Realtime-backed QR pairing flow, and
transactions/budgets reads and writes. It runs on local seeded demo data
until you point it at a real project; then it switches over automatically.

1. Create a project at [supabase.com](https://supabase.com).
2. Open **SQL Editor** → paste in `supabase-schema.sql` → Run. This creates
   `profiles`, `categories`, `transactions`, `budgets`, and `pairing_codes`,
   seeds the default categories, and turns on RLS so users only ever
   read/write their own rows.
3. Under **Authentication → Providers**, enable:
   - **Email** (for the Email tab)
   - **Phone** (for the Mobile/OTP tab) — needs an SMS provider (Twilio, MessageBird, etc.) configured under Auth settings
4. Under **Project settings → API**, copy your `Project URL` and `anon`
   public key — see **Secrets setup** below for where these go
   (`config.js` locally, repo secrets for the GitHub Pages deploy).
   `USE_SUPABASE` flips on automatically once both are set, and every
   screen (auth, dashboard, transactions, budgets) starts reading from
   and writing to your Supabase project instead of `localStorage`.
5. **QR login** — the web client now inserts a row into `pairing_codes` and
   listens on Realtime for it to be claimed. The one piece that has to live
   outside this repo is a small **Supabase Edge Function** the mobile app
   calls after scanning: it validates the code and sets `user_id` +
   `claimed_at` on that row *using the service-role key*, server-side. That
   indirection is required — the browser's anon key can never be allowed to
   sign in as someone else directly. A minimal version:
   ```ts
   // supabase/functions/claim-pairing-code/index.ts
   import { createClient } from 'jsr:@supabase/supabase-js@2';
   Deno.serve(async (req) => {
     const { code } = await req.json();
     const authHeader = req.headers.get('Authorization')!; // the mobile app's user JWT
     const userClient = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authHeader } } });
     const { data: { user } } = await userClient.auth.getUser();
     if (!user) return new Response('Unauthorized', { status: 401 });
     const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
     const { error } = await admin.from('pairing_codes').update({ user_id: user.id, claimed_at: new Date().toISOString() }).eq('code', code).is('claimed_at', null);
     return new Response(error ? error.message : 'ok', { status: error ? 400 : 200 });
   });
   ```
   Deploy with `supabase functions deploy claim-pairing-code`. Without this
   function deployed, the QR tab's "Simulate scan" button still works as a
   stand-in — it signs the demo/local user in directly so the screen is
   fully clickable either way.

## 3. Secrets setup
There are two genuinely different kinds of "key" in this project — they get
protected differently, and conflating them is the most common mistake here.

**a) `SUPABASE_URL` + anon key (public by design)**
This is what the browser uses to talk to Supabase directly, so it always
ends up visible in the deployed site — that's expected. Supabase's real
protection is the Row Level Security policies in `supabase-schema.sql`,
which restrict every row to its own owner regardless of who holds this key.
Keeping it out of the *repo* is still worth doing (lets you rotate it
without a commit, and point dev/staging/prod at different projects):

1. `cp config.example.js config.js` locally, fill in your Supabase project's
   URL and anon key (Project Settings → API). `config.js` is already in
   `.gitignore` — it will never be committed.
2. For the GitHub Pages deploy, add the same two values as **repo secrets**
   instead: **Settings → Secrets and variables → Actions → New repository
   secret** → add `SUPABASE_URL` and `SUPABASE_ANON_KEY`. The included
   `.github/workflows/deploy.yml` generates `config.js` from those secrets
   at build time and deploys the result — the values never touch git
   history, only the built site.

**b) Service-role key and any third-party API keys (true secrets)**
These must never reach the browser. `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
and `SUPABASE_SERVICE_ROLE_KEY` are already auto-injected into every Edge
Function's environment by Supabase — you don't set those yourself. You only
need to set a secret manually for something extra a function calls out to
(a payment gateway, a third-party SMS/email API, etc.):
```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set THIRD_PARTY_API_KEY=sk_live_xxxxx
# or from a file:
supabase secrets set --env-file .env.secrets   # keep this file out of git too
supabase secrets list      # confirm what's set (values are never shown back)
```
Read a secret inside a function with `Deno.env.get('THIRD_PARTY_API_KEY')` —
exactly how `claim-pairing-code` below already reads the service-role key.

## 4. Put it on GitHub
This environment can't reach GitHub directly (no network access here), but
the project is ready to push:
```bash
cd paisapulse
git init
git add .
git commit -m "Initial commit: PaisaPulse expense tracker"
git branch -M main
git remote add origin https://github.com/<your-username>/paisapulse.git
git push -u origin main
```
`config.js` and any `.env*` files are already excluded via `.gitignore` — see
**Secrets setup** above before your first commit if you've already created
`config.js` locally, so it doesn't slip in.

To deploy automatically on every push: **Settings → Pages → Source: GitHub
Actions** (the included `.github/workflows/deploy.yml` handles the rest,
as long as the `SUPABASE_URL`/`SUPABASE_ANON_KEY` repo secrets from
**Secrets setup** are set).

## App structure (for reference)
- **Auth** — Email / Mobile / QR tabs, all leading to the same session.
- **Home** — balance card, this month's income vs. spend, category
  breakdown (donut), 6-month trend (bar), recent transactions.
- **Transactions** — full history, searchable, filterable by type or category,
  grouped by month.
- **Add transaction** — bottom sheet reachable from Home, the nav bar's
  center button, or the Transactions page; expense/income toggle with
  category picker.
- **Budgets** — monthly limit per category with progress bars and
  over-budget flags.
- **Profile** — account details, theme toggle (light/dark), export, logout.
