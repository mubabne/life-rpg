import http from 'node:http';
import {readFile} from 'node:fs/promises';
import {resolve,extname,sep} from 'node:path';
const root=resolve('build/web');
const types={'.html':'text/html','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.css':'text/css','.png':'image/png','.svg':'image/svg+xml','.otf':'font/otf','.ttf':'font/ttf'};
http.createServer(async(req,res)=>{
  const path=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));
  if(path!==root&&!path.startsWith(root+sep)){res.writeHead(403);res.end();return;}
  const target=path===root?resolve(root,'index.html'):path;
  try{const data=await readFile(target);res.writeHead(200,{'Content-Type':types[extname(target)]??'application/octet-stream','Cache-Control':'no-store'});res.end(data);}
  catch{res.writeHead(404);res.end('Not found');}
}).listen(8317,'127.0.0.1',()=>console.log('Life RPG preview: http://127.0.0.1:8317'));
