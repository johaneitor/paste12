# paste12 – API

## Endpoints

- `GET /api/health` → `{"ok": true}`
- `GET /api/notes?page=N` → lista de notas (20 por página, orden desc)
- `POST /api/notes`  
  Cuerpos soportados:
  - **JSON**: `{"text":"hola","hours":24}`
  - **form-data**: `text=...&hours=...`
  - **x-www-form-urlencoded**: `text=...&hours=...`
  - **querystring** (no recomendado en producción)

Respuesta `201`: `{"id": <int>, "ok": true}`

## Campos
- `text` (obligatorio)  
- `hours` (opcional, 1..720; por defecto 24)

## Deploy (Render)
- Build: `pip install -r requirements.txt`
- Start: `gunicorn "backend:create_app()" --bind 0.0.0.0:$PORT --workers=2 --threads=4 --timeout 120`
- Env: `DATABASE_URL=postgres://...` (o `...?sslmode=require` si aplica)

## Notas técnicas
- `Note.author_fp` con índice por `Column(index=True)` (sin `Index(...)` explícito) para evitar duplicados.
- `create_note` tolera JSON/form/urlencoded/query y normaliza `hours` al rango [1..720].
