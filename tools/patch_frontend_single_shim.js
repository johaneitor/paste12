(function(){
  if (document.getElementById('single-note-shim')) return;
  const s = document.createElement('script'); s.id='single-note-shim';
  s.textContent = `
  (function(){
    const B = document.body;
    const isSingle = B && B.getAttribute('data-single') === '1';
    const noteId   = B && B.getAttribute('data-note-id');
    if (!isSingle || !noteId) return;

    // Desactiva initializers de feed comunes si existen
    try { window.__DISABLE_FEED_INIT__ = true; } catch(e){}

    const root = document.getElementById('app') || document.body;
    root.innerHTML = '<div id="single-card" style="max-width:720px;margin:24px auto;padding:16px;border:1px solid #ddd;border-radius:12px;font-family:system-ui"></div>';
    const host = location.origin;

    function h(t){ return t.replace(/[&<>"']/g, s => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[s])); }

    fetch(\`\${host}/api/notes/\${noteId}\`)
      .then(r=>r.json()).then(j=>{
        const it = (j && (j.item||j)) || {};
        const el = document.getElementById('single-card');
        el.innerHTML = \`
          <div style="font-size:14px;color:#666;margin-bottom:8px">Nota #\${it.id}</div>
          <div style="white-space:pre-wrap;font-size:16px;margin-bottom:12px">\${h(it.text||'')}</div>
          <div style="display:flex;gap:8px;align-items:center">
            <button id="btnLike"  style="padding:6px 10px;border:1px solid #ccc;border-radius:8px">👍 <span id="lk">\${it.likes||0}</span></button>
            <button id="btnRepo"  style="padding:6px 10px;border:1px solid #ccc;border-radius:8px">🚩</button>
            <button id="btnShare" style="padding:6px 10px;border:1px solid #ccc;border-radius:8px">🔗 Compartir</button>
          </div>\`;

        // Contar view al abrir
        fetch(\`\${host}/api/notes/\${noteId}/view\`, {method:'POST'}).catch(()=>{});

        const lk = document.getElementById('lk');
        document.getElementById('btnLike').onclick = () => {
          fetch(\`\${host}/api/notes/\${noteId}/like\`, {method:'POST'}).then(r=>r.json()).then(x=>{
            if (typeof x.likes === 'number') lk.textContent = x.likes;
          }).catch(()=>{});
        };
        document.getElementById('btnRepo').onclick = () => {
          fetch(\`\${host}/api/notes/\${noteId}/report\`, {method:'POST'}).catch(()=>{});
          alert('Gracias por reportar.');
        };
        document.getElementById('btnShare').onclick = async () => {
          const url = \`\${location.origin}/?id=\${noteId}\`;
          try{ await navigator.share({url}); }catch(_){
            try{ await navigator.clipboard.writeText(url); alert('Enlace copiado'); }catch(e){ prompt('Copiá el enlace:', url); }
          }
        };
      }).catch(()=>{
        const el = document.getElementById('single-card');
        if (el) el.innerHTML = '<div style="color:#b00">No se pudo cargar la nota.</div>';
      });
  })();`;
  document.documentElement.appendChild(s);
})();
