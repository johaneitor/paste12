(function(){
  function initAdsLazy(){
    try {
      var ads = document.querySelectorAll('ins.adsbygoogle');
      if (!ads || ads.length === 0) return;
      ads.forEach(function(el){
        el.style.minHeight = el.style.minHeight || '120px';
      });
      var io = new IntersectionObserver(function(entries){
        entries.forEach(function(e){
          if (!e.isIntersecting) return;
          try{ (window.adsbygoogle = window.adsbygoogle || []).push({}); }catch(_){ }
          io.unobserve(e.target);
        });
      }, { root: null, rootMargin: '100px', threshold: 0.01 });
      ads.forEach(function(el){ io.observe(el); });
    } catch (_) {}
  }
  if ('requestIdleCallback' in window) {
    requestIdleCallback(initAdsLazy, { timeout: 2000 });
  } else {
    window.addEventListener('load', function(){ setTimeout(initAdsLazy, 0); });
  }
})();
