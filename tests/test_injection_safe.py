import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from wsgi import _inject_index_flags


def test_inject_index_flags_preserves_braces_and_adds_script():
    html = """<!doctype html><html><head><style>body{background:{color};}</style></head><body>{content}</body></html>"""
    out = _inject_index_flags(html)
    # braces content should be preserved (we never call .format())
    assert '{color}' in out
    assert '{content}' in out
    # app.js must be injected exactly once
    assert out.count('/js/app.js') == 1
