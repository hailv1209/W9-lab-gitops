"""
GitOps Dashboard Backend — Flask API
Giao tiếp với K8s (Rollout) + Prometheus (metrics/alerts)
"""
import os
import time
import threading
import requests
from flask import Flask, jsonify, send_from_directory, request

app = Flask(__name__, static_folder="fe", static_url_path="")

# --- Config ---
K8S_API = "https://kubernetes.default.svc"
K8S_TOKEN_FILE = "/var/run/secrets/kubernetes.io/serviceaccount/token"
NAMESPACE = os.getenv("NAMESPACE", "demo")
PROM_URL = os.getenv("PROM_URL", "http://kube-prometheus-stack-prometheus.monitoring.svc:9090")
ARGO_NS = os.getenv("ARGO_NS", "argo-rollouts")

# --- K8s helpers ---
def k8s_headers():
    with open(K8S_TOKEN_FILE) as f:
        token = f.read().strip()
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }

def k8s_get(path):
    url = f"{K8S_API}{path}"
    r = requests.get(url, headers=k8s_headers(), verify="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt", timeout=10)
    r.raise_for_status()
    return r.json()

# --- Prometheus helpers ---
def prom_query(query):
    url = f"{PROM_URL}/api/v1/query"
    r = requests.get(url, params={"query": query}, timeout=10)
    r.raise_for_status()
    data = r.json()
    if data["status"] != "success":
        return None
    results = data["data"]["result"]
    if not results:
        return None
    return float(results[0]["value"][1])

def prom_query_range(query, start, end, step="15s"):
    url = f"{PROM_URL}/api/v1/query_range"
    r = requests.get(url, params={"query": query, "start": start, "end": end, "step": step}, timeout=10)
    r.raise_for_status()
    data = r.json()
    if data["status"] != "success":
        return []
    return data["data"]["result"]

# --- Error injection state ---
error_injecting = False
error_rate = 0.0
inject_lock = threading.Lock()

def set_error_rate(rate):
    global error_injecting, error_rate
    with inject_lock:
        error_injecting = rate > 0
        error_rate = rate
        # Update ConfigMap in cluster
        try:
            cm_patch = {
                "data": {
                    "ERROR_RATE": str(rate),
                    "INJECTING": "true" if rate > 0 else "false"
                }
            }
            requests.patch(
                f"{K8S_API}/api/v1/namespaces/{NAMESPACE}/configmaps/api-error-config",
                headers=k8s_headers(),
                json=cm_patch,
                verify="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt",
                timeout=10
            )
        except Exception:
            pass  # ConfigMap may not exist, that's OK

# =============================================================================
# API Endpoints
# =============================================================================

@app.get("/")
def serve_index():
    return send_from_directory(app.static_folder, "index.html")

@app.get("/api/status")
def api_status():
    """Tổng hợp trạng thái hệ thống"""
    try:
        # Rollout status
        rollout = k8s_get(f"/apis/argoproj.io/v1alpha1/namespaces/{NAMESPACE}/rollouts/api")
        rs = rollout.get("status", {})
        phase = rs.get("phase", "Unknown")
        current = rs.get("currentPodHash", "N/A")
        available = rs.get("availableReplicas", 0)

        # Prometheus metrics
        success_rate = prom_query(
            f'sum(rate(flask_http_request_total{{app="api",status!~"5.."}}[5m]))'
            f' / sum(rate(flask_http_request_total{{app="api"}}[5m]))'
        ) or 0.0

        error_rate_val = prom_query(
            f'sum(rate(flask_http_request_total{{app="api",status=~"5.."}}[5m]))'
            f' / sum(rate(flask_http_request_total{{app="api"}}[5m]))'
        ) or 0.0

        p95 = prom_query(
            f'histogram_quantile(0.95, sum(rate(flask_http_request_duration_seconds_bucket{{app="api"}}[5m])) by (le))'
        ) or 0.0

        # Alert status
        alerts = k8s_get(f"/api/v1/namespaces/{NAMESPACE}/prometheusrules/api-slo-alerts/status")
        firing = alerts.get("active", [])

        # Argo Rollouts available
        try:
            argo_version = k8s_get("/apis/argoproj.io/v1alpha1")["apiVersion"]
            argo_ok = True
        except Exception:
            argo_ok = False

        return jsonify({
            "rollout": {
                "phase": phase,
                "currentVersion": current,
                "availableReplicas": available,
            },
            "metrics": {
                "successRate": round(success_rate * 100, 2),
                "errorRate": round(error_rate_val * 100, 2),
                "p95Latency": round(p95 * 1000, 1),  # ms
                "sloTarget": 95,
            },
            "alerts": {
                "firingCount": len(firing),
                "firing": [a["name"] for a in firing],
            },
            "argoRollouts": argo_ok,
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.get("/api/metrics/history")
def api_metrics_history():
    """Lịch sử metrics trong N phút"""
    minutes = int(request.args.get("minutes", 30))
    end = time.time()
    start = end - minutes * 60

    sr = prom_query_range(
        f'sum(rate(flask_http_request_total{{app="api",status!~"5.."}}[1m]))'
        f' / sum(rate(flask_http_request_total{{app="api"}}[1m]))',
        start, end, "1m"
    )

    er = prom_query_range(
        f'sum(rate(flask_http_request_total{{app="api",status=~"5.."}}[1m]))'
        f' / sum(rate(flask_http_request_total{{app="api"}}[1m]))',
        start, end, "1m"
    )

    return jsonify({
        "successRate": sr,
        "errorRate": er,
    })

@app.post("/api/error/inject")
def api_inject_error():
    """Bật error injection (% lỗi)"""
    rate = float(request.json.get("rate", 0.3))
    set_error_rate(rate)
    return jsonify({"errorInjecting": rate > 0, "errorRate": rate})

@app.post("/api/error/stop")
def api_stop_error():
    """Tắt error injection"""
    set_error_rate(0)
    return jsonify({"errorInjecting": False, "errorRate": 0})

@app.get("/api/error/inject")
def api_get_error_state():
    with inject_lock:
        return jsonify({"errorInjecting": error_injecting, "errorRate": error_rate})

@app.post("/api/rollout/rollback")
def api_rollback():
    """Trigger rollback bằng cách revert git"""
    # Revert via kubectl exec vào một pod có git
    # Đơn giản: return instruction cho user
    return jsonify({
        "message": "Để rollback, chạy: git revert HEAD && git push",
        "instruction": "Rollback phải qua Git để giữ GitOps integrity"
    })

@app.get("/healthz")
def healthz():
    return "ok", 200
