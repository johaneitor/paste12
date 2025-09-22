def install_adsense_injector(app, client_id: str):
    """
    Inserta el tag de AdSense en <head> de cualquier HTML 200 text/html servido
    si aún no está presente.
    """
    if not client_id:
        return
    tag = (
        '<script async '
        'src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client='
        + client_id +
        '" crossorigin="anonymous"></script>'
    )

    @app.after_request
    def _inject(resp):
        try:
            ct = (resp.headers.get("Content-Type") or "").lower()
            if resp.status_code == 200 and "text/html" in ct:
                body = resp.get_data(as_text=True)
                if "pagead2.googlesyndication.com/pagead/js/adsbygoogle.js" not in body \
                   and "</head>" in body:
                    resp.set_data(body.replace("</head>", tag + "\n</head>", 1))
        except Exception:
            # Nunca romper la respuesta por el inyector
            pass
        return resp
