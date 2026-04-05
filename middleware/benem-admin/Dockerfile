FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Run as non-root
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser \
    && mkdir -p /app/log \
    && chown -R appuser:appgroup /app/log
USER appuser

# /app/log is a Docker volume for the audit log
# /data is the bhnm-apns db volume, mounted read-only
VOLUME ["/app/log"]

EXPOSE 8001

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"]
