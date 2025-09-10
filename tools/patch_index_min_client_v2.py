#!/usr/bin/env python3
import re, sys, pathlib, shutil

CANDIDATES = [pathlib.Path(p) for p in (
    "backend/static/index.html",
    "frontend/index.html",
    "index.html",
)]
targets = [p for p in CANDIDATES if p.exists()]
if not targets:
    print("✗ No encontré index.html (backend/static/, frontend/, o raíz)."); sys.exit(2)

MIN_CLIENT = r'''
<script id="p12-min-client">
(()=>{const $=s=>document.querySelector(s),$$=s=>Array.from(document.querySelectorAll(s));
async function unregisterSW(){try{if("serviceWorker"in navigator){(await navigator.serviceWorker.getRegistrations()).forEach(r=>r.unregister())}}catch{}}
function el(t,props={},...kids){const n=document.createElement(t);Object.assign(n,props);kids.flat().forEach(k=>n.append(k));return n}
const host=(location.origin||"").replace(/\/$/,"");
const root=document.getElementById("p12-notes")||(function(){const d=el("div",{id:"p12-notes",style:"max-width:720px;margin:12px auto;padding:0 12px"});document.body.appendChild(d);return d})();
const moreBtn=el("button",{type:"button",textContent:"Cargar más",style:"margin:12px 0; display:none; padding:.6rem 1rem; border-radius:10px; border:1px solid #ddd; background:#fff; cursor:pointer"});root.after(moreBtn);
let nextUrl=null;

function renderItems(items){for(const it of (items||[])){const card=el("div",{className:"p12-card",style:"padding:12px;border:1px solid #eee;border-radius:12px;margin:8px 0;background:#fff"});const txt=el("div",{textContent:(it.text??it.title??"")});const meta=el("div",{style:"opacity:.7;font-size:.85em;margin-top:6px",textContent:`#${it.id} · likes:${it.likes??0}`});card.append(txt,meta);root.append(card)}}

async function fetchPage(url){const res=await fetch(url,{credentials:"include"});const data=await res.json().catch(()=>({ok:false,error:"json"}));if(!res.ok){throw new Error(data?.error||("HTTP "+res.status));} renderItems(data.items||[]); // next
 nextUrl=null; const link=res.headers.get("Link")||res.headers.get("link");
 if(link){const m=/<([^>]+)>;\s*rel="?next"?/i.exec(link); if(m) nextUrl=m[1];}
 if(!nextUrl){try{const xn=JSON.parse(res.headers.get("X-Next-Cursor")||"null"); if(xn&&xn.cursor_ts&&xn.cursor_id){nextUrl=`/api/notes?cursor_ts=${encodeURIComponent(xn.cursor_ts)}&cursor_id=${xn.cursor_id}`}}catch{}}
 moreBtn.style.display=nextUrl?"":"none";}

function pickTextarea(){return $('textarea[name=text]')||$('#text')||document.querySelector('textarea[placeholder]')||$('textarea');}
function pickTTL(){return $('select[name=hours]')||$('select[name=ttl]')||$('input[name=ttl_hours]')||document.querySelector('select');}

async function publish(ev){if(ev&&ev.preventDefault)ev.preventDefault(); const ta=pickTextarea(); const ttlSel=pickTTL();
 const text=(ta?.value||"").trim(); if(!text){alert("Escribe algo primero"); return;}
 const payload={text}; if(ttlSel){const v=Number(ttlSel.value||ttlSel.getAttribute("value")||12); if(Number.isFinite(v)&&v>0) payload.ttl_hours=v;}
 const res=await fetch("/api/notes",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(payload),credentials:"include"});
 const data=await res.json().catch(()=>({ok:false,error:"json"}));
 if(!res.ok || data?.ok===false){throw new Error(data?.error||("HTTP "+res.status));}
 try{ta.value="";}catch{}
 const item=data.item||{id:data.id,text:payload.text,likes:data.likes};
 root.prepend(el("div",{textContent:`#${item.id} · ${item.text}`,style:"padding:10px;margin:6px 0;background:#f5fff5;border:1px solid #dfe;border-radius:10px"}));}

function bindPublish(){const form=document.querySelector("form"); if(form){form.addEventListener("submit",e=>publish(e).catch(err=>alert("Error publicando: "+err.message)));}
 const btn=$$("button, input[type=submit]").find(b=>/publicar|enviar/i.test((b.textContent||b.value||""))); if(btn && !btn.form){btn.addEventListener("click",e=>publish(e).catch(err=>alert("Error publicando: "+err.message)));}}

function start(){unregisterSW(); bindPublish(); fetchPage("/api/notes?limit=10").catch(e=>root.append(el("div",{style:"color:#b00;margin-top:8px"},"Error cargando notas: ", e.message)));}

moreBtn.addEventListener("click",()=>{if(nextUrl) fetchPage(nextUrl).catch(()=>{})});
if(document.readyState==="loading"){document.addEventListener("DOMContentLoaded",start);}else{start();}
})();
</script>
'''.strip()+"\n"

for p in targets:
    html = p.read_text(encoding="utf-8")
    if 'id="p12-min-client"' in html:
        print(f"OK: {p} ya tiene el mini-cliente (no cambio)."); continue

    # insertar antes de </body> (case-insensitive) usando función (evita escapes/backrefs)
    def repl(m): return MIN_CLIENT + "</body>"
    if re.search(r"</body\s*>", html, flags=re.I):
        new = re.sub(r"</body\s*>", repl, html, flags=re.I, count=1)
    else:
        # si no hay </body>, lo agregamos al final
        new = html.rstrip() + "\n" + MIN_CLIENT + "</body>\n"

    bak = p.with_suffix(".html.min_client.bak")
    if not bak.exists():
        shutil.copyfile(p, bak)
    p.write_text(new, encoding="utf-8")
    print(f"patched: mini-cliente (publish + paginación + unregister SW) en {p} | backup={bak.name}")

print("Listo.")
