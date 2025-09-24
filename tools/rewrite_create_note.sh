#!/usr/bin/env bash
set -euo pipefail

F="render_entry.py"
[ -f "$F" ] || { echo "[!] No existe $F"; exit 1; }

BKP="$F.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "$F" "$BKP"

awk '
BEGIN {in_block=0}
{
  if ($0 ~ /^@api\.post\(\"\/notes\"\)/) {
    in_block=1
    print $0
    getline
    print "def create_note():"
    print "    from sqlalchemy.exc import SQLAlchemyError"
    print "    try:"
    print "        data = request.get_json(silent=True) or {}"
    print "        text = (data.get(\"text\") or \"\").strip()"
    print "        if not text:"
    print "            return jsonify(error=\"text required\"), 400"
    print "        try: hours = int(data.get(\"hours\", 24))"
    print "        except Exception: hours = 24"
    print "        hours = min(168, max(1, hours))"
    print "        now = _now()"
    print "        n = Note(text=text, timestamp=now, expires_at=now + timedelta(hours=hours), author_fp=_fp())"
    print "        db.session.add(n)"
    print "        db.session.commit()"
    print "        return jsonify(_note_json(n, now)), 201"
    print "    except SQLAlchemyError as e:"
    print "        db.session.rollback()"
    print "        return jsonify(ok=False, error=\"create_failed\", detail=str(e)), 500"
    print "    except Exception as e:"
    print "        return jsonify(ok=False, error=\"create_failed\", detail=str(e)), 500"
    next
  }
  if (in_block==1) {
    if ($0 ~ /^@/ || $0 ~ /^def[[:space:]]/ || $0 ~ /register_blueprint\(/) {
      in_block=0
      print $0
    }
    else { next }
  } else { print $0 }
}
' "$F" > "$F.tmp" && mv "$F.tmp" "$F"

python -m py_compile "$F" || { echo "[x] Error. Backup: $BKP"; exit 1; }
echo "[✓] create_note() reescrito. Backup en: $BKP"
