// Copy this file to config.js and fill in your own project's values.
// config.js is git-ignored — it never gets committed, so your keys
// never end up in the repo's history. See README → "Secrets setup".
//
// SUPABASE_URL and SUPABASE_ANON_KEY are both meant to be public —
// Supabase's real protection is the Row Level Security policies in
// supabase-schema.sql, not hiding this key. Keeping it out of git is
// still good hygiene (lets you rotate it without a commit, keeps
// different environments — dev/staging/prod — pointing at different
// projects), just don't mistake it for a true secret.

window.__PAISAPULSE_CONFIG__ = {
SUPABASE_URL: 'https://motvvmhnhhuoqobhqqzl.supabase.co',       // e.g. 'https://xxxxx.supabase.co'
  SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1vdHZ2bWhuaGh1b3FvYmhxcXpsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAzNTQ1OTEsImV4cCI6MjEwNTkzMDU5MX0.8IU4MmZxuKRC4D2dmZ8AjDXsFqOY8LhbgNL6wrEQumc',  // Project Settings → API → "anon public" key
};

