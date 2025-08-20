(()=> {
  function dedupe(){
    const cards = Array.from(document.querySelectorAll('.note-card[data-id]'));
    const seen = new Set();
    let removed = 0;
    for(const c of cards){
      const id = c.dataset.id;
      if(!id) continue;
      if(seen.has(id)){ c.remove(); removed++; }
      else seen.add(id);
    }
    return removed;
  }

  // corre al cargar y luego cada 1.5s
  const run = ()=>{ try{ dedupe(); }catch{} };
  document.addEventListener('DOMContentLoaded', run, {once:true});
  setInterval(run, 1500);

  // si hay mutaciones (llegan nuevas notas), dedupe inmediato
  try{
    const mo = new MutationObserver(()=>{ try{ dedupe(); }catch{} });
    mo.observe(document.documentElement, {childList:true, subtree:true});
  }catch{}
})();
