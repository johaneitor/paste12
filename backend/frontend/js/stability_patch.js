(()=> {
  // --- Fetch timeout wrapper for /api/* calls to avoid UI hangs ---
  try{
    const origFetch = window.fetch.bind(window);
    const DEFAULT_TIMEOUT_MS = 7000;
    window.fetch = function(input, init){
      try{
        const url = (typeof input === 'string') ? input : (input && input.url) || '';
        const isApi = typeof url === 'string' && /\/api\//.test(url);
        if (!isApi) return origFetch(input, init);
        const opts = Object.assign({}, init||{});
        // Respect existing AbortController if provided
        if (!opts.signal && typeof AbortController !== 'undefined'){
          const ac = new AbortController();
          opts.signal = ac.signal;
          const to = setTimeout(()=>{ try{ ac.abort(); }catch{} }, DEFAULT_TIMEOUT_MS);
          return origFetch(input, opts).finally(()=>{ clearTimeout(to); });
        }
        return origFetch(input, opts);
      }catch(_){ return origFetch(input, init); }
    };
  }catch{}

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
