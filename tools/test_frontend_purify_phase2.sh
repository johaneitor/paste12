#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"
if [[ -z "$BASE" ]]; then
  echo "Uso: $0 <BASE_URL>" >&2; exit 2
fi

PASS=0; FAIL=0; WARN=0
ok(){ echo "OK  - $*"; ((PASS++))||true; }
ko(){ echo "FAIL- $*"; ((FAIL++))||true; }

# /terms y /privacy deben existir (200)
code_terms="$(curl -fsS -o /dev/null -w '%{http_code}' "${BASE%/}/terms" || true)"
code_priv="$(curl -fsS -o /dev/null -w '%{http_code}' "${BASE%/}/privacy" || true)"
[[ "$code_terms" == "200" ]] && ok "terms 200" || ko "terms http $code_terms"
[[ "$code_priv" == "200" ]] && ok "privacy 200" || ko "privacy http $code_priv"

# Footer con ambos enlaces
tmp_html="$(mktemp)"
curl -fsS "${BASE%/}/?debug=1&nosw=1&v=$(date +%s)" -o "$tmp_html"
grep -qiE '<footer' "$tmp_html" && ok "footer presente" || ko "falta footer"
grep -qiE 'href="/terms"' "$tmp_html" && ok "footer → /terms" || ko "falta link /terms"
grep -qiE 'href="/privacy"' "$tmp_html" && ok "footer → /privacy" || ko "falta link /privacy"

echo "RESUMEN: PASS=$PASS FAIL=$FAIL WARN=$WARN"
[[ $FAIL -eq 0 ]] || exit 1
