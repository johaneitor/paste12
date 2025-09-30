import json,sys
p=sys.argv[1]
data=json.load(open(p))
if isinstance(data, dict) and 'data' in data: data=data['data']
print("id,name,type,url,repo,branch")
for s in (data if isinstance(data,list) else [data]):
    if not isinstance(s,dict): continue
    print("{},{},{},{},{},{}".format(
        s.get("id",""),
        (s.get("name") or "").replace(","," "),
        s.get("type",""),
        (s.get("url") or ""),
        (s.get("repo") or ""),
        (s.get("branch") or "")
    ))
