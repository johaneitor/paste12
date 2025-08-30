from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from fastapi.responses import JSONResponse

limiter = Limiter(key_func=get_remote_address)

def setup_rate_limit(app):
    app.state.limiter = limiter
    @app.exception_handler(RateLimitExceeded)
    def ratelimit_handler(request, exc):
        return JSONResponse({"detail":"Too Many Requests"}, status_code=429)
