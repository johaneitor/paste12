# proxy WSGI -> render_entry.app (por si el Start Command sigue con "wsgi:app")
from render_entry import app as application
# alias común por si gunicorn busca "app"
app = application
