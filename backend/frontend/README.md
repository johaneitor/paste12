# Frontend (Paste12)

This frontend is a lightweight, dependency-free UI served by the backend. It renders a list of notes and provides simple interactions (create, like, view, report).

## Files
- `index.html`: shell document. The backend injects the following flags at runtime to guarantee consistency:
  - `<meta name="p12-commit" ...>`
  - `<meta name="p12-safe-shim" content="1">`
  - `<body data-single="1">`
- `css/`: stylesheets (versioned by query `?v=`). Long-cache headers are set by the backend for these assets.
- `js/app.js`: main UI logic (create + list + like + load-more).
- `js/actions.js`, `js/actions_menu.js`, `js/views_counter.js`: optional enhancements (report/view counters, menus).

## Backend relationship
The UI talks only to canonical endpoints exposed by the Flask backend:
- GET `/api/notes?limit=N&before_id=<id>` → list of notes (supports both `[{...}]` and `{notes:[...]}` shapes).
- POST `/api/notes` (JSON or form): `{ text, hours | ttlHours | ttl_hours }` → creates note.
- POST `/api/notes/:id/like` → increments likes.
- POST `/api/notes/:id/view` → increments views (UI may throttle client-side; server enforces rate limits).
- POST `/api/notes/:id/report` → registers a report; backend enforces deletion after ≥3 distinct reporters.

Legacy alias `/api/report` is deprecated and returns 404; the UI must use `/api/notes/:id/report`.

## JSON shape tolerance
`js/app.js` supports three BE responses for listing:
- `[{...}]` (array)
- `{ notes: [...] }`
- `{ items: [...] }` (diag/legacy)

## Caching
- HTML (`/`, `/index.html`): `Cache-Control: no-store` (to always fetch the latest commit + flags).
- Static assets (`/css/`, `/js/`, `/img/`): `Cache-Control: public, max-age=604800` (7 days). When bumping asset versions, increase the `?v=` query in the HTML or migrate to hashed filenames.

## SPA fallback
This UI is not a full SPA router. If you add client-side routes, create a fallback that maps non-API routes to `index.html` (currently not required).

## Development
- Open `index.html` locally or run the backend to serve it with correct flags and headers.
- To adjust rate limits or CORS, edit `backend/__init__.py`.
- For UI rendering quirks, check `js/app.js` (list binding uses `#notes-list` if present, otherwise creates it).
