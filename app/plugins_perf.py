from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from starlette.middleware.gzip import GZipMiddleware

try:
    from brotli_asgi import BrotliMiddleware
    _BROTLI = True
except Exception:
    _BROTLI = False

def setup_perf(app: FastAPI) -> None:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"], allow_credentials=True,
        allow_methods=["*"], allow_headers=["*"]
    )
    app.add_middleware(GZipMiddleware, minimum_size=512)
    if _BROTLI:
        app.add_middleware(BrotliMiddleware, quality=5)

    @app.middleware("http")
    async def add_caching_headers(request: Request, call_next):
        resp: Response = await call_next(request)
        if request.method == "GET" and request.url.path.startswith(("/static", "/public", "/api/cacheable")):
            resp.headers["Cache-Control"] = "public, max-age=86400, stale-while-revalidate=600"
        return resp
