/**
 * Set Script Properties: LIFE_RPG_ENDPOINT, LIFE_RPG_SECRET, LIFE_RPG_MAILBOX.
 * Authorize once in Apps Script; no Gmail OAuth is needed in Flutter.
 * Label messages with LifeRPG/Quests. Emails containing quest JSON are imported
 * as-is; any other email is sent to the server, where GPT turns its actionable
 * items into quests (requires OPENAI_API_KEY in Supabase Edge Function secrets).
 */
function ingestLifeRpgQuests() {
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(1000)) return;
  try {
    var props = PropertiesService.getScriptProperties();
    var endpoint = props.getProperty('LIFE_RPG_ENDPOINT');
    var secret = props.getProperty('LIFE_RPG_SECRET');
    var mailbox = props.getProperty('LIFE_RPG_MAILBOX');
    if (!endpoint || !secret || !mailbox) throw new Error('Set the three Life RPG Script Properties first.');
    var seen = JSON.parse(props.getProperty('LIFE_RPG_RECEIPTS') || '{}');
    var now = Date.now();
    Object.keys(seen).forEach(function(id) { if (now - seen[id] > 90 * 86400000) delete seen[id]; });
    var offset = Number(props.getProperty('LIFE_RPG_SCAN_OFFSET') || '0');
    var threads = GmailApp.search('label:"LifeRPG/Quests" newer_than:90d', offset, 25);
    threads.forEach(function(thread) {
      thread.getMessages().forEach(function(message) {
        var id = message.getId();
        if (seen[id] || now - message.getDate().getTime() > 90 * 86400000) return;
        try {
          var batch = extractLifeRpgBatch(message.getPlainBody());
          var envelope = {mailbox: mailbox, message_id: id};
          if (batch) envelope.batch = batch;
          else envelope.email = {subject: message.getSubject() || '', body: message.getPlainBody().slice(0, 12000)};
          var response = UrlFetchApp.fetch(endpoint, {
            method: 'post', contentType: 'application/json',
            headers: {'X-Life-RPG-Secret': secret},
            payload: JSON.stringify(envelope),
            muteHttpExceptions: true
          });
          var receipt;
          try { receipt = JSON.parse(response.getContentText()); } catch (_) { throw new Error('Invalid server response.'); }
          if (response.getResponseCode() !== 200 || receipt.ok !== true) throw new Error(receipt.error || 'Import not committed.');
          message.markRead();
          seen[id] = now;
          props.setProperty('LIFE_RPG_RECEIPTS', JSON.stringify(seen));
        } catch (error) {
          console.warn('Quest message ' + id + ' was not imported: ' + error.message);
        }
      });
    });
    props.setProperty('LIFE_RPG_SCAN_OFFSET', threads.length < 25 ? '0' : String(offset + threads.length));
    props.setProperty('LIFE_RPG_RECEIPTS', JSON.stringify(seen));
  } finally { lock.releaseLock(); }
}

// Returns the quest JSON in the email, or null so the server can read it with GPT.
function extractLifeRpgBatch(body) {
  var match = body.match(/LIFE_RPG_JSON_BEGIN\s*([\s\S]*?)\s*LIFE_RPG_JSON_END/);
  var text = match ? match[1] : body.trim().replace(/^```(?:json)?\s*/, '').replace(/\s*```$/, '');
  try { var parsed = JSON.parse(text); return parsed && parsed.schema_version ? parsed : null; }
  catch (_) { return null; }
}

function installLifeRpgTrigger() {
  var existing = ScriptApp.getProjectTriggers().some(function(t) { return t.getHandlerFunction() === 'ingestLifeRpgQuests'; });
  if (!existing) ScriptApp.newTrigger('ingestLifeRpgQuests').timeBased().everyMinutes(5).create();
}
