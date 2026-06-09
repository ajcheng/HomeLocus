FROM python:3.12-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
RUN mkdir -p /data/media-gateway/uploads
ENV UPLOAD_DIR=/data/media-gateway/uploads
ENV PORT=8780
EXPOSE 8780
CMD ["gunicorn", "-b", "0.0.0.0:8780", "-w", "2", "--timeout", "120", "app:app"]
