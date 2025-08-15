import socket, itertools
from backend import create_app
from waitress import serve

app = create_app()

# --- Elegir primer puerto libre ---
for PORT in itertools.chain([8000, 8080], range(8001, 8101)):
    with socket.socket() as s:
        if s.connect_ex(("127.0.0.1", PORT)) != 0:
            break  # encontrado

if __name__ == "__main__":
    print(f"✓ Servidor en http://127.0.0.1:{PORT}")
    serve(app, listen=f"0.0.0.0:{PORT}")
