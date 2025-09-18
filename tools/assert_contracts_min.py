#!/usr/bin/env python3
import sys, json, urllib.request, urllib.error, os

BASE = sys.argv[1] if len(sys.argv)>1 else ""
if not BASE: sys.exit("uso: assert_contracts_min.py https://host")

def req(path, method="GET", headers=None, data=None):
    r = urllib.request.Request(BASE+path, method=method, headers=headers or {}, data=data)
    try:
        with urllib.request.urlopen(r, timeout=20) as resp:
            return resp.status, resp.getheaders(), resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.headers.items(), e.read()

# /api/health
st, hdrs, body = req("/api/health")
assert 200 <= st < 300, f"/api/health {st}"
ct = dict((k.lower(), v) for k,v in hdrs).get("content-type","")
assert ct.startswith("application/json"), f"health content-type inesperado: {ct}"

# Preflight
st, hdrs, _ = req("/api/notes", "OPTIONS", {
    "Origin": "https://example.com",
    "Access-Control-Request-Method": "POST",
})
assert st == 204, f"preflight: {st}"
h = dict((k.lower(), v) for k,v in hdrs)
for k in [
  "access-control-allow-origin", "access-control-allow-methods",
  "access-control-allow-headers", "access-control-allow-credentials",
  "vary"
]:
    assert k in h, f"preflight missing header: {k}"

print("OK: contratos mínimos de health y CORS validados")
