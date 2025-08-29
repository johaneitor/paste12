# WSGI proxy -> entry_main.app (nombre nuevo para evitar bytecode cache)
from entry_main import app as application
# alias común
app = application
