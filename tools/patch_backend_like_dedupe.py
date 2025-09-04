#!/usr/bin/env python3
import re, sys, pathlib, shutil, datetime

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")

changed = []

# 0) backup seguro (reversible)
ts = datetime.datetime.utcnow().strftime("%Y%m%d_%H%M%S")
bakdir = pathlib.Path("tools/backups/wsgiapp"); bakdir.mkdir(parents=True, exist_ok=True)
bak = bakdir / f"__init__.py.{ts}.bak"
shutil.copy2(P, bak)

# 1) Bootstrap: crear like_log si no existe
if "CREATE TABLE IF NOT EXISTS like_log(" not in s:
    block = r'''
            CREATE TABLE IF NOT EXISTS like_log(
                id SERIAL PRIMARY KEY,
                note_id INTEGER NOT NULL,
                fingerprint VARCHAR(128) NOT NULL,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );
        '''
    # Intentamos ubicarlo junto a otras tablas de logs
    anchors = [
        "CREATE TABLE IF NOT EXISTS report_log(",
        "CREATE TABLE IF NOT EXISTS view_log(",
        "CREATE TABLE IF NOT EXISTS note("
    ]
    placed = False
    for anchor in anchors:
        if anchor in s:
            s = s.replace(anchor, anchor + "\n" + block)
            placed = True
            break
    if not placed:
        s += "\n" + block + "\n"
    changed.append("create like_log")

# 1b) Índice único (dedupe fuerte)
if "uq_like_note_fp" not in s:
    idx_stmt = '            cx.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp ON like_log (note_id, fingerprint)"))\n'
    # Pégalo cerca de otros índices/boots (dentro de with eng.begin() as cx:)
    s = re.sub(r'(\s*with\s+eng\.begin\(\)\s+as\s+cx:\s*\n)', r'\1' + idx_stmt, s, count=1)
    changed.append("unique index like_log")

# 2) Reemplazo/inyección del handler 'like'
like_pat = re.compile(r"(?s)elif\s+action\s*==\s*['\"]like['\"]\s*:\s*(.*?)\n\s*(elif|#|return|$)")

like_body = r"""
    # Like con dedupe por fingerprint (1 por persona)
    try:
        # fingerprint: header X-FP o REMOTE_ADDR|User-Agent
        fp = (env.get('HTTP_X_FP') or '').strip()
        if not fp:
            ip = env.get('REMOTE_ADDR','').strip()
            ua = env.get('HTTP_USER_AGENT','').strip()
            fp = f"{ip}|{ua}" if (ip or ua) else 'anon'
        with _engine().begin() as cx:
            from sqlalchemy import text as _text
            # Si ya había like registrado, no sumamos
            seen = cx.execute(_text(
                "SELECT 1 FROM like_log WHERE note_id=:id AND fingerprint=:fp LIMIT 1"
            ), {"id": note_id, "fp": fp}).first()
            if not seen:
                try:
                    cx.execute(_text(
                        "INSERT INTO like_log(note_id, fingerprint, created_at) VALUES (:id, :fp, NOW())"
                    ), {"id": note_id, "fp": fp})
                except Exception:
                    # Si colisiona unique, ignoramos
                    pass
                cx.execute(_text("UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id"), {"id": note_id})
            counts = cx.execute(_text("SELECT likes, views, reports FROM note WHERE id=:id"), {"id": note_id}).first()
            likes = int(counts[0] or 0)
            views = int(counts[1] or 0)
            reports = int(counts[2] or 0)
        return 200, {"ok": True, "id": note_id, "likes": likes, "views": views, "reports": reports}
    except Exception as e:
        return 500, {"ok": False, "error": str(e)}
    """

if like_pat.search(s):
    s = like_pat.sub("elif action == 'like':\n" + like_body + r"\n\2", s, count=1)
    changed.append("replace like action")
else:
    # Insertar antes de 'elif action == "view"' o 'report' si existen
    ins_pt = re.search(r"elif\s+action\s*==\s*['\"]view['\"]\s*:", s) or re.search(r"elif\s+action\s*==\s*['\"]report['\"]\s*:", s)
    if ins_pt:
        s = s[:ins_pt.start()] + "elif action == 'like':\n" + like_body + "\n" + s[ins_pt.start():]
        changed.append("inject like action")
    else:
        # Último recurso: agregar al final de _handle_action
        mfun = re.search(r"(def\s+_handle_action\s*\([^)]*\):)", s)
        if mfun:
            insert_at = mfun.end()
            s = s[:insert_at] + "\n    # injected like handler\n    elif action == 'like':\n" + like_body + "\n" + s[insert_at:]
            changed.append("append like action")

# 3) Guardar
P.write_text(s, encoding="utf-8")
print("patched:", ", ".join(changed), "| backup:", bak)
