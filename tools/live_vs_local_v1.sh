#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL OUTDIR}"
OUTDIR="${2:-/sdcard/Download}"
mkdir -p "$OUTDIR"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
PFX="$OUTDIR/live-vs-local-$TS"
REDIR_OPTS=(-L -H "Cache-Control: no-cache" -H "Pragma: no-cache" -H "Accept-Encoding: identity")

# --- localizar index local ---
cands=("backend/static/index.html" "static/index.html" "public/index.html" "index.html" "wsgiapp/templates/index.html")
LOCAL_INDEX=""
for f in "${cands[@]}"; do [[ -f "$f" ]] && { LOCAL_INDEX="$f"; break; }; done
if [[ -z "$LOCAL_INDEX" ]]; then
  echo "ERROR: no encontré index local (probé: ${cands[*]})" | tee "${PFX}-summary.txt"
  exit 2
fi
LOCAL_ROOT="$(dirname "$LOCAL_INDEX")"

# helpers
sha(){ # sha256 y bytes
  if [[ -f "$1" ]]; then
    printf "%s\t%s\n" "$(sha256sum "$1" | awk '{print $1}')" "$(wc -c < "$1" | tr -d ' ')"
  else
    printf "MISS\t0\n"
  fi
}
sha_url(){ # sha256 y bytes de una URL
  local url="$1"
  local tmp; tmp="$(mktemp)"; trap 'rm -f "$tmp"' RETURN
  if curl -fsS "${REDIR_OPTS[@]}" "$url" -o "$tmp" ; then
    sha "$tmp"
  else
    printf "MISS\t0\n"
  fi
}

# --- fetch index remoto + headers ---
curl -fsSI "${REDIR_OPTS[@]}" "$BASE" > "${PFX}-index-remote-headers.txt" || true
curl -fsS  "${REDIR_OPTS[@]}" "$BASE" > "${PFX}-index-remote.html" || true
cp -f "$LOCAL_INDEX" "${PFX}-index-local.html"

# --- commits (deploy-stamp o meta) ---
remote_commit="$(curl -fsS "${REDIR_OPTS[@]}" "$BASE/api/deploy-stamp" 2>/dev/null | sed -n 's/.*"commit"[": ]*\([0-9a-f]\{7,40\}\).*/\1/p' || true)"
if [[ -z "$remote_commit" ]]; then
  remote_commit="$(sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/p' "${PFX}-index-remote.html" | head -n1)"
fi
local_commit_head="$(git rev-parse HEAD)"
local_commit_meta="$(sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/p' "$LOCAL_INDEX" | head -n1)"

# --- flags FE (shim + single) ---
has_shim_remote="$(grep -qi 'p12-safe-shim' "${PFX}-index-remote.html" && echo yes || echo no)"
has_shim_local="$(grep -qi 'p12-safe-shim' "$LOCAL_INDEX" && echo yes || echo no)"
has_single_remote="$(grep -qi 'name="p12-single"' "${PFX}-index-remote.html" || grep -qi 'data-single="' "${PFX}-index-remote.html" && echo yes || echo no)"
has_single_local="$(grep -qi 'name="p12-single"' "$LOCAL_INDEX" || grep -qi 'data-single="' "$LOCAL_INDEX" && echo yes || echo no)"

# --- tamaño e integridad del index ---
read remote_sha remote_len < <(sha "${PFX}-index-remote.html")
read local_sha  local_len  < <(sha "$LOCAL_INDEX")

# --- extraer assets del index (JS/CSS) ---
extract_assets(){
  # imprime rutas relativas (con barra inicial si vienen así), ignora http(s) externos y data:
  sed -n 's/.*<script[^>]*src=["'\'']\([^"'\'']*\)["'\''][^>]*>.*/\1/pI; s/.*<link[^>]*rel=["'\'']stylesheet["'\''][^>]*href=["'\'']\([^"'\'']*\)["'\''][^>]*>.*/\1/pI' "$1" \
  | sed -E 's/#.*$//' | grep -vE '^(https?:|data:|//)' | sed -E 's@^\./@@' | sed -E 's@^/@/@'
}
mapfile -t assets < <(extract_assets "${PFX}-index-remote.html" | sort -u)
: > "${PFX}-assets-compare.tsv"
printf "asset\tremote_sha\tremote_len\tlocal_sha\tlocal_len\tstatus\n" >> "${PFX}-assets-compare.tsv"

status_overall_assets="OK"
for a in "${assets[@]}"; do
  # normalizar URL y path local
  path_rel="${a#/}"               # quitar leading slash si existe
  url="$BASE/${path_rel}"
  read r_sha r_len < <(sha_url "$url")
  read l_sha l_len < <(sha "$LOCAL_ROOT/$path_rel")
  st="OK"
  if [[ "$r_sha" == "MISS" && "$l_sha" == "MISS" ]]; then st="MISS_BOTH"; status_overall_assets="MISMATCH"
  elif [[ "$r_sha" == "MISS" ]]; then st="MISS_REMOTE"; status_overall_assets="MISMATCH"
  elif [[ "$l_sha" == "MISS" ]]; then st="MISS_LOCAL"; status_overall_assets="MISMATCH"
  elif [[ "$r_sha" != "$l_sha" ]]; then st="MISMATCH"; status_overall_assets="MISMATCH"
  fi
  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$a" "$r_sha" "$r_len" "$l_sha" "$l_len" "$st" >> "${PFX}-assets-compare.tsv"
done

# --- negativos 404 ---
id="999999999"
like_code="$(curl -fsS -X POST -o /dev/null -w "%{http_code}" "$BASE/api/notes/$id/like")" || true
view_g_code="$(curl -fsS -X GET  -o /dev/null -w "%{http_code}" "$BASE/api/notes/$id/view")" || true
view_p_code="$(curl -fsS -X POST -o /dev/null -w "%{http_code}" "$BASE/api/notes/$id/view")" || true
report_code="$(curl -fsS -X POST -o /dev/null -w "%{http_code}" "$BASE/api/notes/$id/report")" || true
neg_line="negativos: like=$like_code view(GET/POST)=$view_g_code/$view_p_code report=$report_code"
echo "$neg_line" > "${PFX}-negative.txt"

# --- resumen ---
{
  echo "== paste12 live vs local @ $TS =="
  echo "BASE: $BASE"
  echo
  echo "-- Commits --"
  echo "remote_commit: ${remote_commit:-unknown}"
  echo "local_head   : $local_commit_head"
  echo "local_meta   : ${local_commit_meta:-none}"
  drift="unknown"
  if [[ -n "${remote_commit:-}" ]]; then
    drift=$([[ "$remote_commit" == "$local_commit_head" ]] && echo "aligned" || echo "DRIFT")
  fi
  echo "drift: $drift"
  echo
  echo "-- Index --"
  echo "remote_len=$remote_len remote_sha=$remote_sha"
  echo "local_len =$local_len  local_sha =$local_sha"
  echo "index_equal: $([[ "$remote_sha" == "$local_sha" ]] && echo yes || echo no)"
  echo "p12-safe-shim: remote=$has_shim_remote local=$has_shim_local"
  echo "single-detector: remote=$has_single_remote local=$has_single_local"
  echo
  echo "-- Assets --"
  echo "assets_total: ${#assets[@]}"
  echo "assets_status: $status_overall_assets"
  echo "assets_report: $(basename "${PFX}-assets-compare.tsv")"
  echo
  echo "-- Negativos --"
  echo "$neg_line"
  echo
  echo "-- Archivos --"
  echo "$(basename "${PFX}-index-remote.html")"
  echo "$(basename "${PFX}-index-local.html")"
  echo "$(basename "${PFX}-index-remote-headers.txt")"
  echo "$(basename "${PFX}-negative.txt")"
} | tee "${PFX}-summary.txt"

echo "Listo. Mirá el resumen: ${PFX}-summary.txt"
