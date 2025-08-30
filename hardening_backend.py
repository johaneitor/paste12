from fastapi import FastAPI, Request
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware

def setup_security(app: FastAPI, allowed_origins: list[str]) -> None:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=allowed_origins,
        allow_credentials=True,
        allow_methods=["GET","POST","OPTIONS"],
        allow_headers=["Content-Type","Authorization"],
        max_age=86400
    )
    @app.middleware("http")
    async def sec_headers(request: Request, call_next):
        resp: Response = await call_next(request)
        resp.headers.setdefault("X-Content-Type-Options","nosniff")
        resp.headers.setdefault("X-Frame-Options","DENY")
        resp.headers.setdefault("Referrer-Policy","no-referrer")
        resp.headers.setdefault("Permissions-Policy","geolocation=(), microphone=(), camera=(), payment=()")
        resp.headers.setdefault("Strict-Transport-Security","max-age=31536000; includeSubDomains; preload")
        return resp
