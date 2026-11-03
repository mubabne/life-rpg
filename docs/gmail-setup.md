# Connect Gmail capture

The `ingest-quests` Edge Function is protected by its own secret header (deploy it with `--no-verify-jwt`). It fails closed until its three private settings are configured. Emails with exact quest JSON are imported as-is; any other email is turned into quests by GPT, which needs `OPENAI_API_KEY` in the same Edge Function secrets.

1. Create your Life RPG account in the app. Confirm the email if requested. Find that account's UUID in Supabase → Authentication → Users.
2. Generate a long random ingestion secret and store it outside this repository.
3. In Supabase → Edge Functions → Secrets, set:
   - `LIFE_RPG_INGEST_USER_ID`: your Life RPG account UUID
   - `LIFE_RPG_MAILBOX`: the Gmail address from which you will import
   - `LIFE_RPG_INGEST_SECRET`: the random ingestion secret
   - `OPENAI_API_KEY`: your OpenAI API key (for plain-English emails)
4. Open Google Apps Script and create a standalone project. Copy `integrations/gmail/Code.gs` into its editor.
5. Set its Script Properties:
   - `LIFE_RPG_ENDPOINT`: `https://jibeofdmyekivzvlhucv.supabase.co/functions/v1/ingest-quests`
   - `LIFE_RPG_MAILBOX`: the same Gmail address
   - `LIFE_RPG_SECRET`: the same random secret
6. In Gmail create the label `LifeRPG/Quests`. Label a real email: either a complete JSON batch that follows `docs/quest-batch.schema.json`, or a plain email such as "Finish the slides by Thursday and call grandma this weekend".
7. Run `ingestLifeRpgQuests` once. Approve Google's requested Gmail and HTTP permissions. Confirm the quests appear in the app and the email becomes read. Re-run to verify no duplicate quests.
8. Run `installLifeRpgTrigger` once to schedule the five-minute check.

Inspect Apps Script executions for failures and the app's Import quests dialog for server receipts. Failed messages are retried as the bounded scan cycles; unread status is not the sole cursor. Checkpoints are per Gmail message ID, while Supabase also deduplicates by planning period. Remove a failed message's label if you want it excluded from future scans.

ChatGPT task notifications contain only a link, so they will not carry quests. Use the app's ✨ button (API) or its "Copy prompt for ChatGPT" + paste flow (subscription) instead. Emails with nothing actionable are marked read and logged as "Needs attention" in the app's quest dialog.
