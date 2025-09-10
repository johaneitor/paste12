#!/usr/bin/env python3
import pathlib, re, shutil, sys

def pick_target():
    for p in [pathlib.Path("backend/static/index.html"),
              pathlib.Path("frontend/index.html"),
              pathlib.Path("index.html")]:
        if p.exists():
            return p
    return None

def restore_from_backup(p: pathlib.Path) -> bool:
    # priorizamos los backups que ya generamos en las sesiones anteriores
    suffixes = [
        ".mini_client_v2.bak",
        ".inline_cors_options_patch.bak",  # por si quedó
        ".patch_deploy_stamp_api.bak",
        ".fix_preflight_position.bak",
        ".fix_preflight_after_assignments.bak",
        ".bak",
    ]
    for suf in suffixes:
        b = p.with_suffix(p.suffix + suf)
        if b.exists():
            shutil.copyfile(b, p)
            print(f"restaurado desde backup: {b.name}")
            return True
    return False

def strip_blocks(s: str) -> str:
    patterns = [
        r'<!--\s*MINI-CLIENT v\d+ START\s*-->.*?<!--\s*MINI-CLIENT v\d+ END\s*-->',
        r'<!--\s*DEBUG-BOOTSTRAP START\s*-->.*?<!--\s*DEBUG-BOOTSTRAP END\s*-->',
        r'<!--\s*PE SHIM START\s*-->.*?<!--\s*PE SHIM END\s*-->',
    ]
    out = s
    for pat in patterns:
        out = re.sub(pat, '\n', out, flags=re.S|re.I)
    # como último recurso: elimina scripts que mencionen mini-client explícitamente
    out = re.sub(r'<script[^>]*>[^<]*(mini-client|SW unregistered|mini v2)[\s\S]*?</script>', '\n', out, flags=re.I)
    return out

p = pick_target()
if not p:
    print("✗ No encontré index.html"); sys.exit(2)

original = p.read_text(encoding="utf-8")
stripped = strip_blocks(original)

if stripped != original:
    p.write_text(stripped, encoding="utf-8")
    print(f"reverted: bloque(s) de cliente/depuración eliminados de {p}")
    sys.exit(0)

if restore_from_backup(p):
    sys.exit(0)

print("OK: nada que revertir (sin bloques ni backups aplicables)")
