import os
from flask import Flask, jsonify
from prometheus_flask_exporter import PrometheusMetrics
app = Flask(__name__)
PrometheusMetrics(app)            # tu dong them /metrics
VER = os.getenv("VERSION", "v1")
@app.get("/")
def index():
    return jsonify(ok=True, version=VER)
@app.get("/healthz")
def healthz(): return "ok", 200
