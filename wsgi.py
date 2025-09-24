# WSGI entrypoint para Gunicorn
# Start Command en Render:
#   gunicorn wsgi:application --chdir /opt/render/project/src -w ${WEB_CONCURRENCY:-2} -k gthread --threads ${THREADS:-4} --timeout ${TIMEOUT:-120} -b 0.0.0.0:$PORT
from backend import app as application  # Gunicorn espera "application"
