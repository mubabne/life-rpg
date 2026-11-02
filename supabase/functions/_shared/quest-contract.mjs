export class ContractError extends Error {}
const stats=['health','mind','craft','social','wealth'];
const object=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
function exact(value,keys,label){
  if(!object(value)||Object.keys(value).length!==keys.length||keys.some(k=>!Object.hasOwn(value,k)))throw new ContractError(`${label} fields do not match schema version 1.`);
}
function date(value){
  if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value))return false;
  const parsed=new Date(`${value}T00:00:00Z`);
  return Number.isFinite(parsed.getTime())&&parsed.toISOString().slice(0,10)===value;
}
export function validateBatch(batch){
  exact(batch,['schema_version','period_type','period_start','timezone','quests'],'Batch');
  if(batch.schema_version!==1||!['weekly','monthly'].includes(batch.period_type))throw new ContractError('Use schema_version 1 and a weekly or monthly period.');
  if(!date(batch.period_start)||typeof batch.timezone!=='string'||batch.timezone.length>100||batch.timezone.length<1)throw new ContractError('A valid period_start and time zone are required.');
  const start=new Date(`${batch.period_start}T00:00:00Z`),end=new Date(start);
  if(batch.period_type==='weekly'){
    if(start.getUTCDay()!==1)throw new ContractError('Weekly periods start Monday.');
    end.setUTCDate(end.getUTCDate()+7);
  }else{
    if(start.getUTCDate()!==1)throw new ContractError('Monthly periods start on the first.');
    end.setUTCMonth(end.getUTCMonth()+1);
  }
  if(!Array.isArray(batch.quests)||batch.quests.length<1||batch.quests.length>40)throw new ContractError('A batch must contain 1–40 quests.');
  const keys=new Set();
  for(const q of batch.quests){
    exact(q,['item_key','title','description','stat_tag','cadence','difficulty','estimated_minutes','due_local_date'],'Quest');
    if(typeof q.item_key!=='string'||!/^[a-z0-9][a-z0-9_-]{0,63}$/.test(q.item_key)||keys.has(q.item_key))throw new ContractError('Each item_key must be valid and unique.');
    keys.add(q.item_key);
    if(typeof q.title!=='string'||q.title.trim().length<1||[...q.title.trim()].length>120||typeof q.description!=='string'||[...q.description].length>2000)throw new ContractError('Invalid quest title or description.');
    if(!stats.includes(q.stat_tag)||!(batch.period_type==='weekly'?['daily','weekly']:['monthly']).includes(q.cadence))throw new ContractError('Invalid stat or cadence for this period.');
    if(!Number.isInteger(q.difficulty)||q.difficulty<1||q.difficulty>3||!Number.isInteger(q.estimated_minutes)||q.estimated_minutes<1||q.estimated_minutes>480)throw new ContractError('Invalid difficulty or estimated minutes.');
    if(!date(q.due_local_date)||q.due_local_date<batch.period_start||new Date(`${q.due_local_date}T00:00:00Z`)>=end)throw new ContractError('Quest dates must fall within the batch period.');
  }
  return batch;
}

export function extractBatch(body){
  if(typeof body!=='string')throw new ContractError('Expected an email body.');
  const match=body.match(/LIFE_RPG_JSON_BEGIN\s*([\s\S]*?)\s*LIFE_RPG_JSON_END/);
  const text=match?match[1]:body.trim().replace(/^```(?:json)?\s*/,'').replace(/\s*```$/,'');
  let parsed;
  try{parsed=JSON.parse(text);}catch{throw new ContractError('The email does not contain a complete quest JSON batch. Use paste import instead.');}
  return validateBatch(parsed);
}
