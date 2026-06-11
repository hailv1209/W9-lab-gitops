# 🧪 HƯỚNG DẪN TEST CANARY DEPLOYMENT

## 📋 MỤC TIÊU TEST

Kiểm tra 3 yêu cầu chính:
1. ✅ **GitOps**: Mọi thay đổi qua Git, rollback < 5 phút
2. ✅ **SLO + Alert**: Alert fire và gửi email khi chất lượng tụt
3. ✅ **Canary tự động**: Bản tốt → 100%, bản lỗi → tự abort

---

## 🚀 BƯỚC 1: CHUẨN BỊ MÔI TRƯỜNG

### 1.1. Kiểm tra các thành phần đã chạy

```powershell
# Kiểm tra ArgoCD
kubectl get pods -n argocd

# Kiểm tra Prometheus & Alertmanager
kubectl get pods -n monitoring

# Kiểm tra Argo Rollouts
kubectl get pods -n argo-rollouts

# Kiểm tra namespace demo
kubectl get all -n demo
```

### 1.2. Cấu hình SMTP cho Alert (BẮT BUỘC)

**Tạo Gmail App Password:**
1. Vào: https://myaccount.google.com/apppasswords
2. Đăng nhập Gmail của bạn
3. Tạo App Password cho "Mail"
4. Copy password (16 ký tự)

**Cập nhật Secret:**
```powershell
# Thay YOUR_APP_PASSWORD_HERE bằng password vừa tạo
kubectl create secret generic alertmanager-email-secret `
  -n demo `
  --from-literal=password='YOUR_APP_PASSWORD_HERE' `
  --dry-run=client -o yaml | kubectl apply -f -
```

**Kiểm tra Secret đã tạo:**
```powershell
kubectl get secret alertmanager-email-secret -n demo
```

### 1.3. Apply tất cả manifests

```powershell
# Apply namespace
kubectl apply -f k8s\namespace.yaml

# Apply API (Rollout + Service + ServiceMonitor)
kubectl apply -f k8s-api\api.yaml

# Apply AnalysisTemplate
kubectl apply -f k8s-api\analysis-template.yaml

# Apply SLO Alert
kubectl apply -f k8s-api\slo-alert.yaml
```

### 1.4. Kiểm tra Rollout ban đầu

```powershell
# Xem trạng thái Rollout
kubectl argo rollouts get rollout api -n demo

# Phải thấy: Status: Healthy, Images: w9-api:1 (stable)
```

---

## 🧪 BƯỚC 2: TEST YÊU CẦU 1 - GITOPS & ROLLBACK < 5'

### Test 2.1: Deploy qua Git (bản tốt)

**Mục tiêu:** Kiểm tra ArgoCD tự động sync khi có thay đổi trong Git.

```powershell
# 1. Thay đổi version trong api.yaml (dòng 27)
# Từ: value: "v3"
# Thành: value: "v4"

# 2. Commit & Push
git add k8s-api\api.yaml
git commit -m "test: deploy api v4"
git push

# 3. Theo dõi ArgoCD sync (mất ~30s)
kubectl get app api -n argocd -w

# 4. Theo dõi Rollout (mất ~3-4 phút)
kubectl argo rollouts get rollout api -n demo -w
```

**Kết quả mong đợi:**
- ArgoCD sync trong ~30 giây
- Rollout chạy canary: 25% → 50% → 100%
- Tất cả pods chạy version mới: `api-v4`

---

### Test 2.2: Rollback qua Git < 5 phút

**Mục tiêu:** Rollback về version cũ trong < 5 phút.

```powershell
# Bắt đầu đếm thời gian!
$startTime = Get-Date

# 1. Revert commit vừa push
git revert HEAD --no-edit
git push

# 2. Đợi ArgoCD sync
kubectl get app api -n argocd -w

# 3. Đợi Rollout hoàn thành
kubectl argo rollouts get rollout api -n demo -w

# Tính thời gian
$endTime = Get-Date
$duration = ($endTime - $startTime).TotalMinutes
Write-Host "⏱️ Rollback time: $duration minutes"
```

**Kết quả mong đợi:**
- ✅ Rollback hoàn thành trong < 5 phút
- ✅ Pods quay về version cũ: `api-v3`

---

## 🔥 BƯỚC 3: TEST YÊU CẦU 2 - SLO & ALERT → EMAIL

### Test 3.1: Kiểm tra SLO baseline (bản tốt)

**Mục tiêu:** Xác nhận API đang chạy tốt, không có alert.

```powershell
# 1. Gửi traffic bình thường (ERROR_RATE=0)
$api_url = "http://$(kubectl get svc api -n demo -o jsonpath='{.spec.clusterIP}'):8080"

# Gửi 100 requests thành công
for ($i=1; $i -le 100; $i++) {
    Invoke-RestMethod -Uri "$api_url/api/data" -Method GET
    Start-Sleep -Milliseconds 100
}

# 2. Kiểm tra metrics trong Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Mở browser: http://localhost:9090
# Query: rate(flask_http_request_total{app="api"}[1m])
```

**Kết quả mong đợi:**
- Success rate: ~100%
- Không có alert fire

---

### Test 3.2: Trigger alert (phá SLO)

**Mục tiêu:** Làm SLO vi phạm → Alert fire → Nhận email.

```powershell
# 1. Deploy bản có lỗi (ERROR_RATE=0.3 = 30% lỗi)
# Sửa file k8s-api\api.yaml (dòng 24-25):
# Từ:
#   - name: ERROR_RATE
#     value: "0"
# Thành:
#   - name: ERROR_RATE
#     value: "0.3"

# 2. Commit & Push
git add k8s-api\api.yaml
git commit -m "test: deploy api with 30% error rate"
git push

# 3. Gửi traffic để tạo metrics
$api_url = "http://$(kubectl get svc api -n demo -o jsonpath='{.spec.clusterIP}'):8080"

for ($i=1; $i -le 200; $i++) {
    try {
        Invoke-RestMethod -Uri "$api_url/api/data" -Method GET
    } catch {
        # Bỏ qua lỗi 500
    }
    Start-Sleep -Milliseconds 100
}

# 4. Theo dõi alerts
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Vào Prometheus: http://localhost:9090/alerts
# Tìm alert: APIHighErrorRate
```

**Kết quả mong đợi:**
- Sau ~2 phút: Alert `APIHighErrorRate` chuyển sang **FIRING**
- Sau ~3-5 phút: **Nhận email** tại `haileab542@gmail.com`
- Email chứa:
  - Subject: `🚨 [CRITICAL] APIHighErrorRate`
  - Nội dung: Success rate < 95%, hướng dẫn rollback

**Kiểm tra email có gửi không:**
```powershell
# Xem logs Alertmanager
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager --tail=100 | Select-String "email"
```

---

## 🤖 BƯỚC 4: TEST YÊU CẦU 3 - CANARY TỰ ĐỘNG

### Test 4.1: Canary thành công (bản tốt → 100%)

**Mục tiêu:** Deploy bản tốt, Canary analysis pass → promote 100%.

```powershell
# 1. Deploy bản tốt (ERROR_RATE=0, version=v5)
# Sửa k8s-api\api.yaml:
# - ERROR_RATE: "0"
# - VERSION: "v5"

git add k8s-api\api.yaml
git commit -m "test: deploy healthy api v5"
git push

# 2. Mở terminal thứ 2 để gửi traffic liên tục
$api_url = "http://$(kubectl get svc api -n demo -o jsonpath='{.spec.clusterIP}'):8080"

while ($true) {
    Invoke-RestMethod -Uri "$api_url/api/data" -Method GET | Out-Null
    Start-Sleep -Milliseconds 500
}

# 3. Theo dõi Rollout (terminal chính)
kubectl argo rollouts get rollout api -n demo -w
```

**Kết quả mong đợi:**
```
Step 1/7: setWeight: 25        ✅ (25% traffic sang canary)
Step 2/7: pause: 30s           ⏸️ (chờ metrics ổn định)
Step 3/7: analysis             🔍 (đo success rate)
  ├─ success-rate: ✅ 100%     (5/5 lần đo pass)
  ├─ error-rate: ✅ 0%
  └─ request-rate: ✅ > 0.1
Step 4/7: setWeight: 50        ✅ (tăng lên 50%)
Step 5/7: pause: 30s           ⏸️
Step 6/7: analysis             🔍 (đo lần 2)
  └─ success-rate: ✅ Pass
Step 7/7: setWeight: 100       🎉 (promote hoàn toàn)

Status: ✅ Healthy
Images: w9-api:v5 (stable)
```

**Thời gian:** ~4-5 phút tổng cộng.

---

### Test 4.2: Canary tự động abort (bản lỗi → rollback)

**Mục tiêu:** Deploy bản lỗi, analysis fail → tự động abort về stable.

```powershell
# 1. Deploy bản lỗi (ERROR_RATE=0.4 = 40% lỗi)
# Sửa k8s-api\api.yaml:
# - ERROR_RATE: "0.4"
# - VERSION: "v6-bad"

git add k8s-api\api.yaml
git commit -m "test: deploy bad api v6"
git push

# 2. Gửi traffic liên tục (terminal thứ 2)
$api_url = "http://$(kubectl get svc api -n demo -o jsonpath='{.spec.clusterIP}'):8080"

while ($true) {
    try {
        Invoke-RestMethod -Uri "$api_url/api/data" -Method GET | Out-Null
    } catch {
        # Bỏ qua lỗi
    }
    Start-Sleep -Milliseconds 500
}

# 3. Theo dõi Rollout
kubectl argo rollouts get rollout api -n demo -w
```

**Kết quả mong đợi:**
```
Step 1/7: setWeight: 25        ✅
Step 2/7: pause: 30s           ⏸️
Step 3/7: analysis             🔍
  ├─ success-rate: ❌ 60%      (< 95% → FAIL)
  ├─ error-rate: ❌ 40%        (> 5% → FAIL)
  └─ Failure count: 2/2        (đạt failureLimit)

🚨 Analysis FAILED → Auto ABORT
⏳ Waiting 30s (abortScaleDownDelaySeconds)
🔄 Scaling down canary pods...

Status: ✅ Healthy (rollback về stable)
Images: w9-api:v5 (stable)      ← Vẫn là version cũ tốt!
```

**Kiểm tra không có downtime:**
```powershell
# Traffic vẫn được phục vụ bởi stable pods
kubectl get pods -n demo -l app=api
# → 4 pods stable vẫn chạy, không bị gián đoạn
```

---

## 📊 BƯỚC 5: XÁC NHẬN ĐẠT YÊU CẦU

### Checklist cuối cùng:

```powershell
# 1. GitOps hoạt động
kubectl get app api -n argocd
# → Status: Synced, Healthy

# 2. Alert đã fire và gửi email
# → Kiểm tra inbox: haileab542@gmail.com
# → Có email với subject "🚨 [CRITICAL] APIHighErrorRate"

# 3. Canary tự động
kubectl argo rollouts list rollouts -n demo
# → Status: Healthy
# → Strategy: Canary with AnalysisTemplate

# 4. Xem lịch sử rollout
kubectl argo rollouts history rollout api -n demo
# → Thấy các revision: v3, v4, v5, v6-bad (aborted)
```

---

## 🎯 KẾT QUẢ MONG ĐỢI

| Yêu cầu | Test | Kết quả |
|---------|------|---------|
| **1. GitOps + Rollback < 5'** | Test 2.1 + 2.2 | ✅ Rollback trong < 5 phút |
| **2. SLO + Alert → Email** | Test 3.2 | ✅ Email nhận được khi SLO vi phạm |
| **3. Canary tự động** | Test 4.1 + 4.2 | ✅ Bản tốt promote, bản lỗi abort |

---

## 🐛 TROUBLESHOOTING

### Vấn đề 1: Không nhận được email

```powershell
# Kiểm tra AlertmanagerConfig
kubectl get alertmanagerconfig -n demo

# Xem logs Alertmanager
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager --tail=50

# Kiểm tra SMTP secret
kubectl get secret alertmanager-email-secret -n demo -o yaml
```

**Nguyên nhân thường gặp:**
- ❌ Chưa tạo Gmail App Password
- ❌ Secret chưa được tạo đúng
- ❌ SMTP bị block (cần bật "Less secure app access")

### Vấn đề 2: Analysis không chạy

```powershell
# Kiểm tra AnalysisRun
kubectl get analysisrun -n demo

# Xem logs chi tiết
kubectl describe analysisrun <name> -n demo
```

**Nguyên nhân thường gặp:**
- ❌ Prometheus không có metrics (chưa có traffic)
- ❌ AnalysisTemplate query sai
- ❌ ServiceMonitor chưa scrape metrics

### Vấn đề 3: Rollout bị stuck

```powershell
# Xem chi tiết
kubectl argo rollouts get rollout api -n demo

# Xem events
kubectl get events -n demo --sort-by='.lastTimestamp'

# Restart rollout
kubectl argo rollouts restart rollout api -n demo
```

---

## 📚 TÀI LIỆU THAM KHẢO

- [Argo Rollouts Docs](https://argoproj.github.io/argo-rollouts/)
- [Prometheus Alerting](https://prometheus.io/docs/alerting/latest/)
- [Gmail App Passwords](https://support.google.com/accounts/answer/185833)

---

## 🎬 VIDEO DEMO (Tùy chọn)

Ghi lại video demo 3 tests trên, gửi kèm:
1. Terminal output
2. Screenshot email nhận được
3. Rollout visualization trong Argo CD UI

**Thời gian demo:** ~15-20 phút tổng cộng.
