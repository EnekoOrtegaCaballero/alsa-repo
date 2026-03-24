FROM python:3.11-slim

WORKDIR /app

# Instalar dependencias del sistema necesarias
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8080

# Usamos gunicorn para producción, no el servidor de desarrollo de Flask
# Asegúrate de deshabilitar el buffering stdout para que Promtail lea los logs JSON en tiempo real
ENV PYTHONUNBUFFERED=1

# Inicia gunicorn y los workers inyectados de forma distribuida
CMD ["opentelemetry-instrument", "gunicorn", "-w", "2", "-b", "0.0.0.0:8080", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
