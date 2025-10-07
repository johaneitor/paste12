FROM python:3.13-slim

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

EXPOSE 8000

CMD ["gunicorn","wsgi:application","-w","2","-k","gthread","--threads","4","--timeout","120","-b","0.0.0.0:8000"]
