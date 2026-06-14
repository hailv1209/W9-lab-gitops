FROM python:3.12-slim
WORKDIR /app
COPY backend/requirements.txt .
RUN pip install --no-cache-dir flask requests prometheus-flask-exporter waitress
COPY backend/app.py .
COPY fe/ ./fe/
EXPOSE 5000
ENV FLASK_APP=app.py
CMD ["python", "-c", "from waitress import serve; from app import app; serve(app, host='0.0.0.0', port=5000)"]
