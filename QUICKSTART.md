# 🚀 Quick Start Guide - Canary Deployment Challenge

## ⚡ Setup nhanh (5 phút)

### Bước 1: Apply tất cả manifests

```bash
# Apply AnalysisTemplate
kubectl apply -f k8s-api/analysis-template.yaml

# Apply SLO & Alerts  
kubectl apply -f k8s-api/slo-alert.yaml

# Apply API Rollout (đã có canary strategy mới)
kubectl apply -f k8s-api/api.yaml
```

### Bước 2: Cấu hình Email Alert (Optional)

```bash
# 1. Sửa email trong file slo-alert.yaml
# Tìm dòng: to: 'your-email@example.com'
# Thay = email của bạn

# 2. Tạo SMTP secret (nếu dùng Gmail)
kubectl create secret generic alertmanager-email-secret \
  -n demo \
  --from-literal=password='your-gmail-app-password'

# Note: Gmail App Password tạo tại: https://myaccount.google.com/apppasswords

# 3. Re-apply
kubectl apply -f k8s-api/slo-alert.yaml
```

### Bước 3: Verify setup

```bash
# Check Rollout
kubectl argo rollouts get rollout api -n demo

# Check AnalysisTemplate
kubectl get analysistemplate -n demo

# Check PrometheusRule
kubectl get prometheusrule -n demo

# Check ServiceMonitor
kubectl get servicemonitor -n demo
```

---

## 🧪 Chạy Test

### Option A: Dùng script tự động (Recommended)

**Linux/Mac:**
```bash
chmod +x test-canary.sh
./test-canary.sh
```

**Windows PowerShell:**
```powershell
.\test-canary.ps1
```

### Option B: Test thủ công

#### Test 1: Deploy Good Version ✅

```bash
# 1. Sửa k8s-api/api.yaml
#    ERROR_RATE: "0"
#    VERSION: "v4-good"

# 2. Commit & push
git add k8s-api/api.yaml
git commit -m "test: deploy good version"
git push

# 3. Watch rollout
kubectl argo rollouts get rollout api -n demo --watch

# Expected: Auto-promote to 100%
```

#### Test 2: Deploy Bad Version ❌

```bash
# 1. Sửa k8s-api/api.yaml
#    ERROR_RATE: "0.5"   (50% error)
#    VERSION: "v5-bad"

# 2. Commit & push
git add k8s-api/api.yaml
git commit -m "test: deploy bad version"
git push

# 3. Watch rollout
kubectl argo rollouts get rollout api -n demo --watch

# Expected: Auto-abort, rollback to stable
```

#### Test 3: Git Rollback 🔄

```bash
# 1. Revert commit
git revert HEAD
git push

# 2. Watch ArgoCD sync
kubectl get application api -n argocd -w

# 3. Verify rollback time < 5 minutes
```

---

## 📊 Monitoring & Debug

### Xem Rollout status
```bash
kubectl argo rollouts get rollout api -n demo
```

### Xem AnalysisRun
```bash
# List all
kubectl get analysisrun -n demo -l rollout=api

# Describe latest
kubectl describe analysisrun -n demo -l rollout=api | tail -50
```

### Xem Prometheus metrics
```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Browser: http://localhost:9090
# Query:
sum(rate(flask_http_request_total{app="api", status!~"5.."}[1m])) / sum(rate(flask_http_request_total{app="api"}[1m]))
```

### Xem Alerts
```bash
# List PrometheusRules
kubectl get prometheusrule -n demo

# Check Alertmanager
kubectl port-forward -n monitoring svc/alertmanager-operated 9093:9093
# Browser: http://localhost:9093
```

### Generate traffic để test
```bash
# Get API IP
API_IP=$(kubectl get svc api -n demo -o jsonpath='{.spec.clusterIP}')

# Generate traffic
while true; do curl http://$API_IP:8080/; sleep 0.5; done
```

---

## 🎯 Success Criteria Checklist

- [ ] AnalysisTemplate deployed
- [ ] PrometheusRule & Alert configured
- [ ] Good version → Auto-promote to 100%
- [ ] Bad version → Auto-abort & rollback
- [ ] Git revert → Rollback < 5 minutes
- [ ] Alert fired & email received (if configured)
- [ ] Screenshot/video recorded

---

## 📸 Evidence Collection

### Screenshots cần có:

1. **Rollout với canary strategy**
   ```bash
   kubectl argo rollouts get rollout api -n demo
   ```

2. **AnalysisRun Failed (auto-abort)**
   ```bash
   kubectl describe analysisrun <name> -n demo
   ```

3. **Prometheus metrics**
   - Success rate query
   - Alert firing

4. **Git history**
   ```bash
   git log --oneline --graph -10
   ```

5. **Email alert** (screenshot inbox)

### Video recording tips:

1. Start: Show current stable version
2. Deploy good version: Watch auto-promote
3. Deploy bad version: Watch auto-abort
4. Git revert: Time the rollback
5. Show alert & email

---

## 🐛 Troubleshooting

### Vấn đề: AnalysisRun không chạy

```bash
# Check AnalysisTemplate exists
kubectl get analysistemplate -n demo

# Check Prometheus accessible
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090/-/healthy
```

### Vấn đề: Metrics rỗng

```bash
# Check ServiceMonitor
kubectl get servicemonitor -n demo -o yaml

# Check Prometheus targets
# Port-forward Prometheus UI → Status → Targets
# Tìm "demo/api" → Phải là UP
```

### Vấn đề: Alert không fire

```bash
# Check PrometheusRule
kubectl get prometheusrule -n demo -o yaml

# Check rule trong Prometheus UI
# Port-forward → Alerts → Tìm "APIHighErrorRate"
```

### Vấn đề: Email không gửi

```bash
# Check secret
kubectl get secret alertmanager-email-secret -n demo

# Check Alertmanager config
kubectl get alertmanagerconfig -n demo -o yaml

# Check logs
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager --tail=100
```

---

## 📚 Đọc thêm

- [README-CANARY.md](./README-CANARY.md) - Chi tiết về metrics & query
- [Argo Rollouts Docs](https://argoproj.github.io/argo-rollouts/)
- [Prometheus Query Examples](https://prometheus.io/docs/prometheus/latest/querying/examples/)

---

**Good luck! 🚀**
