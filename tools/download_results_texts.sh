#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; LIMIT="${2:-10}"; OUTDIR="${3:-/sdcard/Download}"
if [[ -z "$BASE" ]]; then echo "Uso: $0 BASE LIMIT OUTDIR"; exit 1; fi
mkdir -p "$OUTDIR"
tmp_json="$(mktemp)"
curl -fsS "$BASE/api/notes?limit=$LIMIT" -o "$tmp_json"

python - <<PY
import json, os, re, sys, datetime, csv
BASE   = ${BASE!r}
LIMIT  = int(${LIMIT})
OUTDIR = ${OUTDIR!r}
with open(${tmp_json!r}, "rb") as f: data = json.load(f)
if not isinstance(data, list):
    data = data.get("items", []) if isinstance(data, dict) else []
def slugify(s, maxlen=32):
    s = s.strip().replace("\n"," "); s = re.sub(r"\s+"," ",s)
    s = re.sub(r"[^a-zA-Z0-9 _.-]","", s); s = s[:maxlen].strip()
    return s or "note"
now = datetime.datetime.utcnow().strftime("%Y%m%d-%H%M%SZ")
summary_md  = os.path.join(OUTDIR, f"paste12_notes_summary_{now}.md")
summary_csv = os.path.join(OUTDIR, f"paste12_notes_{now}.csv")
with open(summary_csv,"w",newline="",encoding="utf-8") as csvf, open(summary_md,"w",encoding="utf-8") as mdf:
    w = csv.writer(csvf); w.writerow(["id","timestamp","expires_at","likes","views","reports","author_fp","text_preview"])
    mdf.write(f"# Export notes ({len(data)} items)\n- Base: {BASE}\n- Generated (UTC): {now}\n- Limit: {LIMIT}\n\n")
    for i,n in enumerate(data,1):
        nid  = n.get("id"); text = n.get("text","") or ""
        ts   = n.get("timestamp",""); exp = n.get("expires_at","")
        lk   = n.get("likes",0); vw = n.get("views",0); rp = n.get("reports",0)
        fp   = n.get("author_fp","")
        preview = (text.replace("\n"," ").strip()[:80] + ("…" if len(text) > 80 else ""))
        w.writerow([nid, ts, exp, lk, vw, rp, fp, preview])
        if text.strip():
            fname = f"note_{nid}_{slugify(preview)}.txt" if nid is not None else f"note_{i}_{slugify(preview)}.txt"
            with open(os.path.join(OUTDIR, fname), "w", encoding="utf-8") as tf: tf.write(text)
            mdf.write(f"## {i}. id={nid} | likes={lk} views={vw} reports={rp}\n- timestamp: {ts}\n- expires_at: {exp}\n- author_fp: {fp}\n- file: {fname}\n\n")
        else:
            mdf.write(f"## {i}. id={nid} (sin texto)\n- timestamp: {ts}\n- expires_at: {exp}\n- author_fp: {fp}\n\n")
print("OK:", summary_md); print("OK:", summary_csv)
PY
rm -f "$tmp_json"
