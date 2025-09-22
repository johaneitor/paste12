#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-${BASE:-}}"
LIMIT="${2:-${LIMIT:-20}}"
OUTDIR="${3:-${OUTDIR:-/sdcard/Download}}"
[[ -z "${BASE}" ]] && { echo "Uso: $0 BASE [LIMIT] [OUTDIR]"; exit 2; }
mkdir -p "$OUTDIR"

tmp_json="$(mktemp)"
trap 'rm -f "$tmp_json"' EXIT

curl -fsS "$BASE/api/notes?limit=${LIMIT}" -o "$tmp_json"

python - <<PY
import json, os, re, csv, datetime, sys
BASE=${BASE!r}
LIMIT=int(${LIMIT})
OUTDIR=${OUTDIR!r}
now=datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%SZ")

with open(${tmp_json!r},"rb") as f:
    data=json.load(f)
if not isinstance(data,list):
    data = data.get("items",[]) if isinstance(data,dict) else []

def slugify(s,maxlen=32):
    s=(s or "").strip().replace("\n"," ")
    s=re.sub(r"\s+"," ",s)
    s=re.sub(r"[^a-zA-Z0-9 _.-]","",s)
    s=s[:maxlen].strip()
    return s or "note"

summary_md=os.path.join(OUTDIR,f"paste12_notes_summary_{now}.md")
summary_csv=os.path.join(OUTDIR,f"paste12_notes_{now}.csv")

with open(summary_csv,"w",newline="",encoding="utf-8") as csvf, open(summary_md,"w",encoding="utf-8") as mdf:
    w=csv.writer(csvf)
    w.writerow(["id","timestamp","expires_at","likes","views","reports","author_fp","text_preview"])
    mdf.write(f"# Export notes ({len(data)} items)\\n")
    mdf.write(f"- Base: {BASE}\\n- Generated (UTC): {now}\\n- Limit: {LIMIT}\\n\\n")
    for i,n in enumerate(data,1):
        nid=n.get("id"); text=n.get("text") or ""
        ts=n.get("timestamp",""); exp=n.get("expires_at","")
        likes=n.get("likes",0); views=n.get("views",0); reps=n.get("reports",0)
        fp=n.get("author_fp","")
        preview=(text.replace("\\n"," ").strip())
        preview=preview[:80]+("…" if len(preview)>80 else "")
        w.writerow([nid,ts,exp,likes,views,reps,fp,preview])
        if text.strip():
            fname=f"note_{nid}_{slugify(preview)}.txt" if nid is not None else f"note_{i}_{slugify(preview)}.txt"
            with open(os.path.join(OUTDIR,fname),"w",encoding="utf-8") as tf: tf.write(text)
            mdf.write(f"## {i}. id={nid} | likes={likes} views={views} reports={reps}\\n")
            mdf.write(f"- timestamp: {ts}\\n- expires_at: {exp}\\n- author_fp: {fp}\\n")
            mdf.write(f"- file: {fname}\\n\\n")
        else:
            mdf.write(f"## {i}. id={nid} (sin texto)\\n- timestamp: {ts}\\n- expires_at: {exp}\\n- author_fp: {fp}\\n\\n")

print("OK:", summary_md)
print("OK:", summary_csv)
PY
