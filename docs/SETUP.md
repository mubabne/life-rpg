# Go live: Supabase + OpenAI + Vercel

About 15 minutes. You need a terminal with Node.js, a Supabase account, a Vercel account and (for the AI button) an OpenAI API account.

## 1. Supabase (database, login, AI functions)

The project `jibeofdmyekivzvlhucv` already has the first migration. If you start a fresh project instead, use its ref below.

```sh
npx supabase login
npx supabase link --project-ref jibeofdmyekivzvlhucv
npx supabase db push                                   # applies 20261103090000_ai_quests.sql
npx supabase functions deploy generate-quests
npx supabase functions deploy ingest-quests --no-verify-jwt
```

From Supabase → Project settings → API keys, copy:

- **Project URL** → `SUPABASE_URL`
- **Publishable key** (`sb_publishable_…`) → `SUPABASE_PUBLISHABLE_KEY`

Never put the service-role / secret key in the app or in Vercel.

## 2. OpenAI (the "Generate quests" button)

1. platform.openai.com → Billing → add a small prepaid credit (for example $5). One weekly plan with `gpt-5-mini` costs well under one cent.
2. API keys → create a key.
3. Store it as a Supabase secret (never in the app):

```sh
npx supabase secrets set OPENAI_API_KEY=sk-...
# optional: npx supabase secrets set OPENAI_MODEL=gpt-5-mini
```

Without this key the app still works; the free "Copy prompt for ChatGPT" + paste flow uses your ChatGPT subscription.

## 3. Vercel (the website)

1. vercel.com → Add New → Project → import `mubabne/life-rpg`. Leave framework as "Other"; `vercel.json` already sets the build.
2. Settings → Environment Variables (Production and Preview):
   - `SUPABASE_URL` = your Project URL
   - `SUPABASE_PUBLISHABLE_KEY` = your publishable key
3. Deploy. The first build downloads Flutter and takes a few minutes.

## 4. Point Supabase login at your site

Supabase → Authentication → URL Configuration:

- **Site URL**: your Vercel URL, e.g. `https://life-rpg.vercel.app`
- **Redirect URLs**: add `https://life-rpg.vercel.app/**` and `https://*-mubabne.vercel.app/**` (preview deploys)

This makes confirmation and password-reset emails open your site. To skip email confirmation while testing, turn off Authentication → Sign In / Providers → Email → "Confirm email".

## 5. Optional: Gmail → quests

See [gmail-setup.md](gmail-setup.md). Any email you label `LifeRPG/Quests` becomes quests: exact quest JSON is imported as-is, and plain English (e.g. "finish report by Friday, call mom") is turned into quests by GPT using the same `OPENAI_API_KEY`.
