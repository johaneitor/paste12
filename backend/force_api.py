from flask import jsonify
def install(app):
    try:
        rules = list(app.url_map.iter_rules())
        have_ping   = any(str(r).rstrip('/') == '/api/ping'    for r in rules)
        have_routes = any(str(r).rstrip('/') == '/api/_routes' for r in rules)
        if not have_ping:
            app.add_url_rule('/api/ping', endpoint='api_ping_wsgi',
                             view_func=(lambda: jsonify({'ok': True, 'pong': True, 'src': 'wsgi'})),
                             methods=['GET'])
        if not have_routes:
            def _dump():
                info=[]
                for r in app.url_map.iter_rules():
                    info.append({'rule': str(r),
                                 'methods': sorted(m for m in r.methods if m not in ('HEAD','OPTIONS')),
                                 'endpoint': r.endpoint})
                info.sort(key=lambda x: x['rule'])
                return jsonify({'routes': info}), 200
            app.add_url_rule('/api/_routes', endpoint='api_routes_dump_wsgi', view_func=_dump, methods=['GET'])
    except Exception:
        pass
