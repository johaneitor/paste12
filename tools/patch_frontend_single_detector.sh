#!/usr/bin/env bash
set -euo pipefail

inject() {
  local f="$1"
  [ -f "$f" ] || return 0
  local bak="${f}.p12_single_detector.bak"
  cp -f "$f" "$bak"
  if grep -qi 'id="p12-single-detector"' "$f"; then
    echo "OK: detector ya presente en $f"
    return 0
  fi
  awk 'BEGIN{done=0}
  {print}
  tolower($0) ~ /<head[^>]*>/ && !done {
    print "<script id=\"p12-single-detector\">"
    print "(()=>{"
    print "  const isSingle = !!document.querySelector(\"meta[name=\\\"p12-single\\\"]\") || (document.body && document.body.getAttribute(\"data-single\")===\"1\");"
    print "  window.__P12_SINGLE__ = isSingle;"
    print "  if(isSingle) document.documentElement.classList.add(\"p12-single\");"
    print "})();"
    print "</script>"
    done=1
  }' "$bak" > "$f"
  echo "patched: $f | backup=$(basename "$bak")"
}

inject backend/static/index.html
inject frontend/index.html
