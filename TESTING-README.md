# 🧪 Hướng dẫn Test Canary Deployment - GitOps

## 📂 Cấu trúc file test

```
├── TEST-GUIDE.md              # Hướng dẫn chi tiết từng bước test
├── test-requirements.ps1      # Script kiểm tra tự động các yêu cầu
├── quick-test.ps1             # Script hướng dẫn test nhanh
└── TESTING-README.md          # File này - tổng quan
```

---

## 🎯 3 Yêu cầu cần test

### 1️⃣ GitOps + Rollback < 5 phút
- ✅ Mọi thay đổi qua Git (ArgoCD auto-sync)
- ✅ Rollback bằng `git revert` trong < 5 phút

### 2️⃣ SLO + Alert → Email
- ✅ 1 SLO: API Success Rate ≥ 95%
- ✅ 1 Alert: Fire khi vi phạm SLO
- ✅ Gửi email đến: haileab542@gmail.com

### 3️⃣ Canary tự động
- ✅ AnalysisTemplate đo metrics tự động
- ✅ Bản tốt → promote 100%
- ✅ Bản lỗi → tự động abort về stable

---

## 🚀 Quick Start - 3 Bước

### BƯỚC 1: Kiểm tra cấu hình

```powershell
# Chạy script kiểm tra tự động
.\test-requirements.ps1
```

**Kết quả mong đợi:**
```
YÊU CẦU 1 (GitOps)    : 3/3 (100%) ✅
YÊU CẦU 2 (SLO+Alert) : 5/5 (100%) ✅
YÊU CẦU 3 (Canary)    : 6/6 (100%) ✅
TỔNG: 14/14 tests passed (100%)
```

**Nếu fail test 2.4 (SMTP Secret):**
```powershell
# Tạo Gmail App Password tại: https://myaccount.google.com/apppasswords
# Sau đó tạo secret:
kubectl create secret generic alertmanager-email-secret `
  -n demo `
  --from-literal=password='your-16-char-app-password'
```

---

### BƯỚC 2: Test từng yêu cầu

```powershell
# Test yêu cầu 1: GitOps
.\quick-test.ps1 1

# Test yêu cầu 2: SLO + Alert
.\quick-test.ps1 2

# Test yêu cầu 3: Canary
.\quick-test.ps1 3

# Hoặc test tất cả
.\quick-test.ps1 all
```

Script sẽ hiển thị:
- Trạng thái hiện tại của hệ thống
- Hướng dẫn chi tiết từng bước test
- Kết quả mong đợi

---

### BƯỚC 3: Test thực tế

Đọc file `TEST-GUIDE.md` để:
- Test chi tiết từng yêu cầu
- Xem hướng dẫn step-by-step có screenshot
- Troubleshooting nếu gặp lỗi

---

## 📊 Test Matrix

| Yêu cầu | Test tự động | Test thủ công | Thời gian |
|---------|--------------|---------------|-----------|
| **1. GitOps** | ✅ Script check config | 🧪 Deploy + Rollback | ~10 phút |
| **2. Alert** | ✅ Script check config | 🧪 Trigger alert + Email | ~5-10 phút |
| **3. Canary** | ✅ Script check config | 🧪 Deploy tốt/lỗi | ~10-15 phút |

**Tổng thời gian:** ~30-40 phút để test đầy đủ.

---

## 🔍 Kiểm tra nhanh từng thành phần

### ArgoCD
```powershell
kubectl get app api -n argocd
kubectl get app api -n argocd -o yaml | Select-String "syncPolicy" -Context 5
```

### Prometheus & Alerts
```powershell
kubectl get prometheusrule -n demo
kubectl get alertmanagerconfig -n demo
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Vào: http://localhost:9090/alerts
```

### Argo Rollouts
```powershell
kubectl argo rollouts list rollouts -n demo
kubectl argo rollouts get rollout api -n demo
kubectl get analysistemplate -n demo
```

### Metrics
```powershell
kubectl get servicemonitor -n demo
kubectl port-forward -n demo svc/api 8080:8080
# Test metrics: curl http://localhost:8080/metrics
```

---

## ✅ Checklist test hoàn chỉnh

### Pre-test
- [ ] ArgoCD đã cài đặt và chạy
- [ ] Prometheus + Alertmanager đã chạy
- [ ] Argo Rollouts đã cài đặt
- [ ] SMTP Secret đã tạo
- [ ] Script `test-requirements.ps1` pass 100%

### Test Yêu cầu 1: GitOps
- [ ] Thay đổi version trong Git
- [ ] ArgoCD auto-sync trong ~30s
- [ ] Rollout deploy thành công
- [ ] Git revert + rollback < 5 phút

### Test Yêu cầu 2: Alert
- [ ] Deploy bản có lỗi (ERROR_RATE=0.3)
- [ ] Gửi traffic để tạo metrics
- [ ] Alert `APIHighErrorRate` fire trong Prometheus
- [ ] Nhận email tại haileab542@gmail.com
- [ ] Email có đủ thông tin (severity, description, runbook)

### Test Yêu cầu 3: Canary
- [ ] **Test 3A - Bản tốt:**
  - [ ] Deploy ERROR_RATE=0
  - [ ] Canary 25% → analysis pass
  - [ ] Canary 50% → analysis pass
  - [ ] Promote 100% thành công
- [ ] **Test 3B - Bản lỗi:**
  - [ ] Deploy ERROR_RATE=0.5
  - [ ] Canary 25% → analysis fail
  - [ ] Auto abort sau 2 failures
  - [ ] Rollback về stable version
  - [ ] Stable pods vẫn chạy, không downtime

---

## 🐛 Troubleshooting

### Lỗi thường gặp

**1. Rollout Degraded: "scaleDownDelaySeconds requires traffic routing"**
```powershell
# Đã fix: xóa scaleDownDelaySeconds trong k8s-api\api.yaml
kubectl apply -f k8s-api\api.yaml
```

**2. Không nhận được email**
```powershell
# Kiểm tra secret
kubectl get secret alertmanager-email-secret -n demo

# Kiểm tra logs Alertmanager
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager --tail=50

# Tạo lại secret nếu cần
kubectl delete secret alertmanager-email-secret -n demo
kubectl create secret generic alertmanager-email-secret `
  -n demo `
  --from-literal=password='your-correct-password'
```

**3. AnalysisTemplate không có metrics**
```powershell
# Kiểm tra ServiceMonitor scrape được metrics
kubectl get servicemonitor api -n demo -o yaml

# Test metrics endpoint
kubectl port-forward -n demo svc/api 8080:8080
curl http://localhost:8080/metrics | Select-String "flask_http_request_total"

# Kiểm tra Prometheus có metrics
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Query: flask_http_request_total{app="api"}
```

**4. ArgoCD không sync**
```powershell
# Kiểm tra Application
kubectl get app api -n argocd -o yaml

# Xem logs ArgoCD
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50

# Force sync
kubectl patch app api -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

---

## 📚 Tài liệu tham khảo

- [TEST-GUIDE.md](./TEST-GUIDE.md) - Hướng dẫn chi tiết
- [README-CANARY.md](./README-CANARY.md) - Tài liệu Canary deployment
- [Argo Rollouts Docs](https://argoproj.github.io/argo-rollouts/)
- [Prometheus Alerting](https://prometheus.io/docs/alerting/latest/)

---

## 🎬 Demo Video (Đề xuất)

Ghi lại video demo 3 tests:

1. **Test 1 (GitOps):** ~5 phút
   - Show git commit + push
   - Show ArgoCD sync
   - Show rollout progress
   - Show git revert + rollback time

2. **Test 2 (Alert):** ~5 phút
   - Deploy bản lỗi
   - Gửi traffic
   - Show Prometheus alert firing
   - Show email nhận được

3. **Test 3 (Canary):** ~10 phút
   - Test 3A: Bản tốt promote
   - Test 3B: Bản lỗi abort

**Công cụ gợi ý:** OBS Studio, ShareX, hoặc Windows Game Bar (Win+G)

---

## 🎉 Kết luận

Sau khi hoàn thành test, bạn sẽ có:

✅ **Proof of Concept** cho 3 yêu cầu đề bài
✅ **Logs & Screenshots** chứng minh
✅ **Email** nhận được từ alert
✅ **Video demo** (optional)

**Chúc bạn test thành công!** 🚀
