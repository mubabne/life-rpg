# Connect Gmail capture

The Edge Function is deployed with JWT verification enabled. It fails closed until its three private settings are configured. No Gmail trigger or ChatGPT schedule has been installed automatically.

1. Create your Life RPG account in the app. Confirm the email if requested. Find that account's UUID in Supabase → Authentication → Users.
2. Generate a long random ingestion secret and store it outside this repository.
3. In Supabase → Edge Functions → Secrets, set:
   - `LIFE_RPG_INGEST_USER_ID`: your Life RPG account UUID
   - `LIFE_RPG_MAILBOX`: the Gmail address from which you will import
   - `LIFE_RPG_INGEST_SECRET`: the random ingestion secret
4. Open Google Apps Script and create a standalone project. Copy `integrations/gmail/Code.gs` into its editor.
5. Set its Script Properties:
   - `LIFE_RPG_ENDPOINT`: `https://jibeofdmyekivzvlhucv.supabase.co/functions/v1/ingest-quests`
   - `LIFE_RPG_MAILBOX`: the same Gmail address
   - `LIFE_RPG_SECRET`: the same random secret
   - `LIFE_RPG_GATEWAY_TOKEN`: the project's **legacy public anon JWT** from Supabase → Project settings → API keys. This satisfies the gateway's JWT verification. Do not use a service-role key. The newer publishable key is used by Flutter; it is not a JWT for this endpoint.
6. In Gmail create the label `LifeRPG/Quests`. Label a real email containing a complete JSON batch that follows `docs/quest-batch.schema.json`.
7. Run `ingestLifeRpgQuests` once. Approve Google's requested Gmail and HTTP permissions. Confirm the quests appear in the app and the email becomes read. Re-run to verify no duplicate quests.
8. Run `installLifeRpgTrigger` once to schedule the five-minute check.

Inspect Apps Script executions for failures and the app's Import quests dialog for server receipts. Failed messages are retried as the bounded scan cycles; unread status is not the sole cursor. Checkpoints are per Gmail message ID, while Supabase also deduplicates by planning period. Remove a failed message's label if you want it excluded from future scans.

ChatGPT task notifications may contain only a link. Verify an actual notification before creating a Gmail filter. If it has no full JSON body, copy the generated JSON from ChatGPT and use the app's paste import. The script never opens private ChatGPT links or guesses missing payloads.

Capture supports structured quest JSON. Converting arbitrary prose emails to quests would require a later parser or LLM API integration.
