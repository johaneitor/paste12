from fastapi import FastAPI
from plugins_perf import setup_perf
from hardening_backend import setup_security
from reports import router as reports_router

def create_app():
    app = FastAPI()
    setup_perf(app)
    setup_security(app, ["https://tu-dominio.com","https://www.tu-dominio.com"])
    app.include_router(reports_router)  # <- monta /api/reports
    return app
