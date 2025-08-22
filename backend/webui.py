from flask import Blueprint, send_from_directory
from pathlib import Path
# Detecta dónde está el frontend (soporta deploy con root en 'backend')
PKG_DIR = Path(__file__).resolve().parent  # .../backend
CANDIDATES = [
    PKG_DIR / 'frontend',                 # backend/frontend (subdir deploy)
    PKG_DIR.parent / 'frontend',          # <repo>/frontend (root deploy)
    Path.cwd() / 'frontend',              # fallback
]
for _cand in CANDIDATES:
    if _cand.exists():
        FRONT_DIR = _cand
        break
else:
    FRONT_DIR = CANDIDATES[0]
webui = Blueprint('webui', __name__)

@webui.route('/', methods=['GET'])
def index():
    return send_from_directory(FRONT_DIR, 'index.html')

@webui.route('/js/<path:fname>', methods=['GET'])
def js(fname):
    return send_from_directory(FRONT_DIR / 'js', fname)

@webui.route('/favicon.ico', methods=['GET'])
def favicon():
    p = FRONT_DIR / 'favicon.ico'
    if p.exists():
        return send_from_directory(FRONT_DIR, 'favicon.ico')
    return ('', 204)
