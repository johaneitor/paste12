import sys, json, urllib.request
BASE=sys.argv[1]
r=urllib.request.Request(BASE+"/api/notes?limit=100000")
with urllib.request.urlopen(r, timeout=20) as resp:
    data=json.loads(resp.read())
n=len(data.get("items",[]))
assert n<=100, f"limit cap roto: devolvió {n} (>100)"
print("OK: cap de limit ≤ 100")
