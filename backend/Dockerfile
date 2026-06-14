FROM python:3.12-slim
WORKDIR /app
COPY backend/requirements.txt .
RUN pip install --no-cache-dir flask requests prometheus-flask-exporter
COPY backend/app.py .
COPY fe/ ./fe/
EXPOSE 5000
ENV FLASK_APP=app.py
CMD ["python", "app.py"]
