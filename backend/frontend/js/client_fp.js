(function(){
  function uuid(){
    if (window.crypto?.randomUUID) return crypto.randomUUID();
    const a = new Uint8Array(16);
    (window.crypto||{}).getRandomValues?.(a);
    return Array.from(a).map(b=>b.toString(16).padStart(2,'0')).join('');
  }
  let t = localStorage.getItem('p12');
  if (!t){ t = uuid(); localStorage.setItem('p12', t); }
  // expón por si se necesita
  window.p12Token = t;

  // Parchea fetch para añadir la cabecera X-User-Token
  const orig = window.fetch;
  window.fetch = function(input, init){
    init = init || {};
    const headers = new Headers(init.headers || {});
    headers.set('X-User-Token', t);
    init.headers = headers;
    return orig(input, init);
  };
  console.log('[client_fp] token listo');
})();
