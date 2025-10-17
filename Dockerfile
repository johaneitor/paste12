FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN useradd --create-home --shell /bin/bash app

WORKDIR /app

# Install dependencies first for better build caching
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copy the rest of the source code
COPY . /app

USER app

# Render expects the app to listen on $PORT (default 10000). Use shell form for env expansion.
EXPOSE 10000

ENV WEB_CONCURRENCY=2 \
    THREADS=4 \
    TIMEOUT=120

CMD ["/bin/sh","-lc","exec gunicorn wsgi:application -w ${WEB_CONCURRENCY} -k gthread --threads ${THREADS} --timeout ${TIMEOUT} -b 0.0.0.0:${PORT:-10000}"]
