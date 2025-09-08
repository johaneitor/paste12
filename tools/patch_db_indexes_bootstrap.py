#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile
W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")
if "\t" in s: s = s.replace("\t","    ")
changed = False

BLOCK = r'''
# === Bootstrap: ensure useful DB indexes (idempotent) ===
try:
    _BOOT_INDEXES_DONE
except NameError:
    try:
        from sqlalchemy import text as _text
    except Exception:
        _text = None
    def _ensure_indexes_once():
        if _text is None:
            return
        try:
            with _engine().begin() as cx:  # type: ignore[name-defined]
                cx.execute(_text("""CREATE INDEX IF NOT EXISTS note_paging_idx ON note (timestamp DESC, id DESC)"""))
                cx.execute(_text("""CREATE INDEX IF NOT EXISTS like_log_note_fp ON like_log(note_id, fingerprint)"""))
        except Exception:
            pass
    try:
        _ensure_indexes_once()
    except Exception:
        pass
    _BOOT_INDEXES_DONE = True
'''
if "_BOOT_INDEXES_DONE" not in s:
    if not s.endswith("\n"): s += "\n"
    s += "\n" + BLOCK.strip() + "\n"
    changed = True

if changed:
    bak = W.with_suffix(".py.patch_boot_indexes.bak")
    if not bak.exists(): shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print("patched: boot indexes | backup=", bak.name)

py_compile.compile(str(W), doraise=True)
print("✓ py_compile OK")
