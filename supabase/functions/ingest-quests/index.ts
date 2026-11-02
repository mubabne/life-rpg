import {ContractError, validateBatch} from '../_shared/quest-contract.mjs';

const json=(body: unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json'}});
async function equalSecret(a:string,b:string){
  const encode=new TextEncoder();
  const [x,y]=await Promise.all([a,b].map(v=>crypto.subtle.digest('SHA-256',encode.encode(v))));
  const left=new Uint8Array(x),right=new Uint8Array(y);
  let diff=0;for(let i=0;i<left.length;i++)diff|=left[i]^right[i];
  return diff===0;
}
async function readLimited(request:Request){
  if(!request.body)throw new ContractError('A JSON request body is required.');
  const reader=request.body.getReader();const decoder=new TextDecoder();let size=0,text='';
  while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>65536){await reader.cancel();throw new ContractError('The request exceeds 64 KB.');}text+=decoder.decode(value,{stream:true});}
  return text+decoder.decode();
}

Deno.serve(async(request:Request)=>{
  if(request.method!=='POST')return json({error:'Use POST.'},405);
  const secret=Deno.env.get('LIFE_RPG_INGEST_SECRET');
  const owner=Deno.env.get('LIFE_RPG_INGEST_USER_ID');
  const mailbox=Deno.env.get('LIFE_RPG_MAILBOX');
  if(!secret||!owner||!mailbox)return json({error:'Email import has not been connected yet.'},503);
  const supplied=request.headers.get('X-Life-RPG-Secret')??'';
  if(!supplied||!await equalSecret(supplied,secret))return json({error:'Unauthorized.'},401);
  let messageId='';
  async function rpc(batch:unknown,failure:string|null=null){
    const response=await fetch(`${Deno.env.get('SUPABASE_URL')}/rest/v1/rpc/life_rpg_ingest`,{
      method:'POST',headers:{'Content-Type':'application/json','apikey':Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,'Authorization':`Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`},
      body:JSON.stringify({owner_id:owner,mailbox,message_id:messageId,batch,failure}),
    });
    const result=await response.json();
    if(!response.ok)throw new ContractError(result.message??'Could not import this batch.');
    return result;
  }
  try{
    let envelope;
    try{envelope=JSON.parse(await readLimited(request));}catch(e){if(e instanceof ContractError)throw e;throw new ContractError('Invalid JSON request.');}
    if(!envelope||Array.isArray(envelope)||Object.keys(envelope).sort().join(',')!=='batch,mailbox,message_id'||envelope.mailbox!==mailbox||typeof envelope.message_id!=='string'||!/^[a-zA-Z0-9_-]{1,200}$/.test(envelope.message_id))throw new ContractError('Invalid message identity or envelope.');
    messageId=envelope.message_id;
    const batch=validateBatch(envelope.batch);
    return json({ok:true,...await rpc(batch)});
  }catch(error){
    const reason=error instanceof ContractError?error.message:'Email import is temporarily unavailable. Try again later.';
    if(messageId){try{await rpc(null,reason);}catch{/* The message remains available for retry in Gmail. */}}
    return json({error:reason},error instanceof ContractError?422:503);
  }
});
