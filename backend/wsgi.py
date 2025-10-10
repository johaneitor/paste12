def _inject_index_flags(html: str) -> str:
    """
    Inserta scripts en HTML de manera segura.
    Evita problemas con llaves {} que podrían romper format() o regex.
    """
    # Inserción segura de app.js
    if "</head>" in html:
        html = html.replace("</head>", " <script src=\"/js/app.js\" defer></script>\n</head>")
    else:
        html += "\n<script src=\"/js/app.js\" defer></script>\n"
    # No alterar llaves: dejar intactas
    return html
