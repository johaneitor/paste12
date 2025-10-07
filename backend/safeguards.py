from __future__ import annotations
from flask import request, jsonify, make_response

def register_api_safeguards(app):
    # 1) Preflight CORS universal para /api/* (204 sin tocar DB)
    @app.before_request
    def _skip_options_preflight():
        if request.method == 'OPTIONS' and request.path.startswith('/api/'):
            resp = make_response(('', 204))
            h = resp.headers
            h['Access-Control-Allow-Origin'] = '*'
            h['Access-Control-Allow-Methods'] = 'GET, POST, HEAD, OPTIONS'
            h['Access-Control-Allow-Headers'] = 'Content-Type'
            h['Access-Control-Max-Age'] = '86400'
            return resp

    # 2) OPTIONS /api/notes si no existe (normalmente lo intercepta el before_request)
    try:
        exists_opt = any((r.rule == '/api/notes' and 'OPTIONS' in r.methods) for r in app.url_map.iter_rules())
    except Exception as exc:
        app.logger.debug('[safeguards] exists_opt check failed: %r', exc)
        exists_opt = False
    if not exists_opt:
        app.add_url_rule('/api/notes', 'api_notes_options_safe',
                         lambda: make_response(('', 204)), methods=['OPTIONS'])

    # 3) Fallback GET /api/notes si no existe (no pisa tu route real)
    try:
        exists_get = any((r.rule == '/api/notes' and 'GET' in r.methods) for r in app.url_map.iter_rules())
    except Exception as ex:
        app.logger.debug('[safeguards] exists_get check failed: %r', ex)
        exists_get = False
    if not exists_get:
        def _api_notes_fallback():
            limit = 10
            try:
                limit = min(max(int(request.args.get('limit', 10)), 1), 50)
            except Exception:
                limit = 10
            data = []
            link = None
            try:
                from .models import Note  # lazy import para evitar ciclos
                rows = Note.query.order_by(getattr(Note, 'timestamp').desc()).limit(limit).all()
                for n in rows:
                    data.append({
                        'id': getattr(n, 'id', None),
                        'text': getattr(n, 'text', ''),
                        'timestamp': getattr(n, 'timestamp', None),
                        'likes': getattr(n, 'likes', 0),
                        'views': getattr(n, 'views', 0),
                    })
                if data and data[-1].get('id') is not None:
                    base = request.url_root.rstrip('/')
                    link = f"{base}/api/notes?limit={limit}&before_id={data[-1]['id']}"
            except Exception as ex:
                app.logger.warning('fallback /api/notes (db issue): %r', ex)
            resp = jsonify(data)
            resp.headers['Access-Control-Allow-Origin'] = '*'
            if link:
                resp.headers['Link'] = f"<{link}>; rel=\"next\""
            return resp, 200
        app.add_url_rule('/api/notes', 'api_notes_fallback_safe', _api_notes_fallback, methods=['GET'])
