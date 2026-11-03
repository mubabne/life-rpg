import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {validateBatch,extractBatch} from '../supabase/functions/_shared/quest-contract.mjs';
const good={schema_version:1,period_type:'weekly',period_start:'2026-11-02',timezone:'Asia/Ulaanbaatar',quests:[{item_key:'walk',title:'Walk outside',description:'Take a short walk.',stat_tag:'health',cadence:'daily',difficulty:1,estimated_minutes:15,due_local_date:'2026-11-02'}]};
test('strict contract rejects malformed dates, duplicate keys, untrusted rewards and nulls',()=>{
  assert.equal(validateBatch(good),good);
  for(const mutate of [b=>b.quests[0].xp_reward=999,b=>b.quests.push({...b.quests[0]}),b=>b.quests[0].due_local_date='2026-02-30',b=>b.quests[0].difficulty='1',b=>b.timezone=null,b=>b.quests[0].title=null]){
    const b=structuredClone(good);mutate(b);assert.throws(()=>validateBatch(b));
  }
});
test('email extraction accepts explicit payloads, not notification links',()=>{
  assert.deepEqual(extractBatch(`Notification\nLIFE_RPG_JSON_BEGIN\n${JSON.stringify(good)}\nLIFE_RPG_JSON_END\nFooter`),good);
  assert.throws(()=>extractBatch('Your task is ready. Open ChatGPT to view it.'),/complete quest JSON/);
  const scope={};vm.createContext(scope);vm.runInContext(readFileSync(new URL('../integrations/gmail/Code.gs',import.meta.url),'utf8'),scope);
  assert.equal(scope.extractLifeRpgBatch(JSON.stringify(good)).quests[0].item_key,'walk');
  // Prose emails are forwarded for GPT conversion instead of failing.
  assert.equal(scope.extractLifeRpgBatch('Open ChatGPT'),null);
});
