# Life RPG

A personal productivity RPG built with Flutter, Riverpod, and Supabase. Turn recurring responsibilities and flexible ChatGPT quests into steady growth across Health, Mind, Craft, Social, and Wealth.

## Included in this MVP

- Email/password account creation and sign-in, plus a read-only sample adventure.
- Daily, weekly, and monthly quests, manual creation, skipping with reasons, and recurring templates.
- Transactional server-side XP, levels, gold, stat XP, and an append-only reward ledger.
- Daily habits with gradual strength decay and two automatic freezes per habit/month.
- A saved review of the last completed week, reflections, and a copyable ChatGPT feedback summary.
- Strict quest JSON import with preview, atomic validation, period deduplication, and shared weekly workload limits for weekly/monthly AI quests.
- A deployed Gmail ingestion endpoint, retry-safe Apps Script source, and import receipts.
- RLS from day one, server-side ownership checks, and explicit function permissions.
- Phone bottom navigation and a responsive desktop/browser layout.

## Go live

Follow [docs/SETUP.md](docs/SETUP.md) to connect Supabase, OpenAI and Vercel.

## AI quests

Tap ✨ in the top bar. **Generate quests** asks GPT (server-side, via the `generate-quests` Edge Function and your `OPENAI_API_KEY`) to plan a balanced week from your review, habits and pending quests, within your weekly budget. **Copy prompt for ChatGPT** gives a ready prompt for your ChatGPT subscription; paste the JSON answer back to import it.

## Run

Install Flutter compatible with Dart 3.13.7 (this project was verified with Flutter 3.47.9). Then:

```sh
flutter pub get
flutter run
```

With no configuration the app opens a **read-only preview**. It does not calculate or award progression locally.

For your own connected account, copy `config/supabase.example.json` to `config/supabase.local.json`, fill in the project URL and public publishable key, and run:

```sh
flutter run --dart-define-from-file=config/supabase.local.json
```

The local project is already configured for the dedicated **Life RPG** Supabase project (`jibeofdmyekivzvlhucv`, Seoul region). Configuration files are ignored by Git. Create an account in the app and confirm its email if requested. Flutter receives only a public key; server secrets never belong in the app.

```sh
flutter run -d chrome --dart-define-from-file=config/supabase.local.json
flutter build apk --debug --dart-define-from-file=config/supabase.local.json
```

An Android SDK is required for a local APK build. The GitHub workflow also builds an installable debug APK and uploads `life-rpg-android-debug` as an artifact. A debug APK is intended for personal testing; a signed store release is a later step.

## Backend

The initial migration has been applied to the dedicated project. The `ingest-quests` Edge Function is deployed with JWT verification enabled, and maintenance runs every 15 minutes. Gmail remains disconnected until you supply an account UUID, mailbox, and ingestion secret and install the Apps Script trigger.

For another Supabase project, initialize/link the Supabase CLI and apply the migrations in `supabase/migrations`. Deploy the function with its configuration. The private schema must **not** be added to the API's exposed schemas.

The public `life_rpg(action,args)` RPC is the user entry point. It requires an authenticated user, locks that user's progression row first, and performs each mutation in one database transaction. Clients cannot write directly to quest state, balances, rewards, or habit outcomes. `life_rpg_ingest` is restricted to the server role and is called only after the Edge Function verifies its dedicated secret.

Cron materializes fixed responsibilities, evaluates closed habit days, and saves weekly reviews. The same maintenance runs when an account loads, so reopening the app catches up after a missed scheduled run. Month-end recurring tasks clamp to the last valid day.

## Game rules

| Action | XP | Gold |
| --- | ---: | ---: |
| Easy quest | 20 | 5 |
| Medium quest | 40 | 10 |
| Hard quest | 80 | 20 |
| Habit check-in | 5 | 0 |

Each reward's XP also contributes to its stat. Level 1 begins at 0 XP. Advancing from level L costs `ceil(100 * L^1.5)` XP, cumulatively. Quest reward values are fixed when the server creates the occurrence.

Habit strength is a fraction from 0 to 1. A completion applies `strength * .9 + .1`; a miss applies `strength * .9`. The first two missed days per habit/calendar month freeze strength and streak and award no XP. Further misses reset the streak and dent strength. Each outcome has a unique local date; changing time zones never rewrites past outcomes.

Weekly reviews use a saved cutoff, preserve skips and unfinished work, and suggest a smaller flexible budget below 50% completion (with at least three eligible quests). Two strong weeks can grow the budget toward your configured capacity. AI batches count monthly work in the same weekly cap. You still manually supply the review to ChatGPT: the app does not automatically share your database with it.

## ChatGPT and Gmail setup

- [Quest JSON contract](docs/quest-batch.schema.json)
- [Scheduled quest prompt](docs/chatgpt-quest-prompt.md)
- [Sample weekly batch](docs/sample-weekly-batch.json) — update its period/dates before importing outside that week
- [Gmail setup](docs/gmail-setup.md)
- [Apps Script source](integrations/gmail/Code.gs)

ChatGPT notification emails are not assumed to contain a full payload. The paste importer is always available. Plain-English emails labelled for import are turned into quests by GPT on the server.

## Verify

```sh
flutter analyze
flutter test
npm ci --ignore-scripts
npm test
```

Backend tests run the actual migration and PL/pgSQL in PGlite, an embedded PostgreSQL runtime. They cover RLS, blocked direct writes, reward replay, ownership, habit deduplication/decay/freezes, month-end recurrence, level boundaries, strict import validation, and email deduplication. They do not emulate the Supabase HTTP gateway or email delivery. A separate rollback-only check was run against the hosted database for RLS and reward replay; Supabase security advisors reported no findings.

The workflow runs Flutter analysis/tests, PostgreSQL/contract tests, and the Android build. Repository variables `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` configure its APK; both are public client configuration. Never put a service-role key in these variables.

## Backlog

Monthly bosses, penalty quests, reward shop, achievements/titles, Android widgets, radar charts, push notifications, offline mutation queues, and signed release distribution.
