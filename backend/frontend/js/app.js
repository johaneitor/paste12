(() => {
  const $ = (sel) => document.querySelector(sel);
  const feedEl = $("#feed");
  const feedMsg = $("#feed-msg");
  const form = $("#note-form");
  const formMsg = $("#form-msg");
  const loadMoreBtn = $("#load-more");

  let nextAfter = null;
  let loading = false;

  function humanTime(iso) {
    if (!iso) return "-";
    try { return new Date(iso).toLocaleString(); } catch { return iso; }
  }

  function renderNote(n) {
    const el = document.createElement("article");
    el.className = "note";
    el.innerHTML = `
      <div class="text">${(n.text || "").replace(/[&<>]/g, s => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[s]))}</div>
      <div class="meta">
        <span>#${n.id}</span>
        <span>ts: ${humanTime(n.timestamp)}</span>
        <span>expira: ${humanTime(n.expires_at) || "-"}</span>
        <span>❤ ${n.likes|0}</span>
        <span>👁 ${n.views|0}</span>
        <span>🚩 ${n.reports|0}</span>
      </div>
    `;
    return el;
  }

  async function fetchPage(afterId=null, limit=20) {
    const u = new URL("/api/notes", location.origin);
    u.searchParams.set("limit", String(limit));
    if (afterId) u.searchParams.set("after_id", String(afterId));
    const res = await fetch(u, { headers: { "Accept": "application/json" }});
    if (!res.ok) throw new Error(`GET /api/notes -> ${res.status}`);
    nextAfter = res.headers.get("X-Next-After");
    const arr = await res.json();
    return Array.isArray(arr) ? arr : [];
  }

  async function loadFirst() {
    if (loading) return;
    loading = true;
    feedMsg.textContent = "Cargando…";
    try {
      feedEl.innerHTML = "";
      const items = await fetchPage(null, 20);
      items.forEach(n => feedEl.appendChild(renderNote(n)));
      feedMsg.textContent = items.length ? "" : "No hay notas aún.";
      loadMoreBtn.hidden = !nextAfter;
    } catch (e) {
      feedMsg.textContent = `Error cargando feed: ${e.message || e}`;
    } finally { loading = false; }
  }

  async function loadMore() {
    if (loading || !nextAfter) return;
    loading = true;
    loadMoreBtn.disabled = true;
    try {
      const items = await fetchPage(nextAfter, 20);
      items.forEach(n => feedEl.appendChild(renderNote(n)));
      loadMoreBtn.hidden = !nextAfter;
    } catch (e) {
      feedMsg.textContent = `Error: ${e.message || e}`;
    } finally {
      loadMoreBtn.disabled = false;
      loading = false;
    }
  }

  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    formMsg.textContent = "";
    const text = $("#note-text").value.trim();
    const hours = Number($("#note-hours").value) || 24;
    if (!text) { formMsg.textContent = "Escribí algo 🙂"; return; }
    try {
      const res = await fetch("/api/notes", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text, hours })
      });
      if (!res.ok) {
        const t = await res.text().catch(()=> "");
        throw new Error(`POST /api/notes -> ${res.status} ${t}`);
      }
      $("#note-text").value = "";
      $("#note-hours").value = "24";
      await loadFirst();
      formMsg.textContent = "Publicado ✔";
      setTimeout(()=> formMsg.textContent = "", 1500);
    } catch (e) {
      formMsg.textContent = e.message || String(e);
    }
  });

  loadMoreBtn.addEventListener("click", loadMore);
  window.addEventListener("load", loadFirst);
})();
