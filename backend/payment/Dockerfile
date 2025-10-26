FROM python:3.13.1-alpine

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

RUN apk update && apk add --no-cache \
    gcc \
    python3-dev \
    postgresql-dev \
    ca-certificates

RUN adduser --disabled-password --gecos "" --uid 1001 appuser

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt gunicorn uvicorn

COPY . .

RUN chown -R appuser /app
USER appuser

CMD gunicorn --bind "0.0.0.0:${PAYMENT_PORT}" -k uvicorn.workers.UvicornWorker app.main:app
