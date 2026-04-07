FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# /data is mounted as a Docker volume for SQLite persistence
VOLUME ["/data"]

# Run as non-root user for security
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser \
    && mkdir -p /data && chown -R appuser:appgroup /data
USER appuser

EXPOSE 8889

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8889"]
