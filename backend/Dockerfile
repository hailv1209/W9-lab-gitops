FROM python:3.12-slim
RUN pip install flask requests prometheus-flask-exporter
WORKDIR /app
COPY app.py .
EXPOSE 5000
ENV FLASK_APP=app.py
CMD ["python", "app.py"]
