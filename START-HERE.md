# 🚀 BẮT ĐẦU TẠI ĐÂY - HƯỚNG DẪN ĐẦY ĐỦ

## 📋 TÓM TẮT DỰ ÁN

Triển khai **Canary Deployment tự động** với GitOps, đáp ứng 3 yêu cầu:

1. ✅ **GitOps**: Mọi thay đổi qua Git, rollback < 5 phút
2. ✅ **SLO + Alert**: Alert fire và gửi email khi chất lượng tụt
3. ✅ **Canary tự động**: Bản tốt → 100%, bản lỗi → tự abort

---

## 🎯 CÁC BƯỚC THỰC HIỆN

### ✅ BƯỚC 1: KIỂM TRA CẤU HÌNH HIỆN TẠI (5 phút)

```powershell
# 1. Chạy script kiểm tra tự động
.\test-requirements.ps1
```

**Kết quả mong đợi:**
```
YÊU CẦU 1 (GitOps)    : 3/3 (100%) ✅
YÊU CẦU 2 (SLO+Alert) : 4/5 (80%)  ⚠️  ← Thiếu SMTP Secret
YÊU CẦU 3 (Canary)    : 6/6 (100%) ✅
```

**Nếu có lỗi:** Xem phần Troubleshooting bên dưới.

---

### ✅ BƯỚC 2: TẠO SMTP SECRET (5 phút)

**Tại sao cần:** Để Alertmanager gửi email khi alert fire.

#### 2.1. Tạo Gmail App Password

1. **Mở browser**, vào: https://myaccount.google.com/apppasswords
2. **Đăng nhập** Gmail: `demeter.web.design.22@gmail.com` (hoặc Gmail của bạn)
3. **Chọn App:** "Mail"
4. **Chọn Device:** "Windows Computer"
5. **Click "Generate"**
6. **Copy password** (16 ký tự, không có khoảng trắng)
   - Ví dụ: `abcd efgh ijkl mnop` → Copy: `abcdefghijklmnop`

#### 2.2. Tạo Kubernetes Secret

```powershell
# Thay YOUR_APP_PASSWORD bằng password vừa copy
kubectl create secret generic alertmanager-email-secret `
  -n demo `
  --from-literal=password='YOUR_APP_PASSWORD' `
  --dry-run=client -o yaml | kubectl apply -f -
```

#### 2.3. Kiểm tra Secret đã tạo

```powershell
kubectl get secret alertmanager-email-secret -n demo
```

**Kết quả mong đợi:**
```
NAME                          TYPE     DATA   AGE
alertmanager-email-secret     Opaque   1      5s
```

---

### ✅ BƯỚC 3: APPLY MANIFESTS (2 phút)

```powershell
# 1. Apply namespace (nếu chưa có)
kubectl apply -f k8s\namespace.yaml

# 2. Apply API Rollout
kubectl apply -f k8s-api\api.yaml

# 3. Apply AnalysisTemplate
kubectl apply -f k8s-api\analysis-template.yaml

# 4. Apply SLO Alert
kubectl apply -f k8s-api\slo-alert.yaml
```

**Kiểm tra:**
```powershell
# Kiểm tra Rollout
kubectl argo rollouts get rollout api -n demo
# → Status: Healthy

# Kiểm tra tất cả resources
kubectl get all,prometheusrule,alertmanagerconfig,servicemonitor -n demo
```

---

### ✅ BƯỚC 4: CHẠY LẠI SCRIPT KIỂM TRA (1 phút)

```powershell
.\test-requirements.ps1
```

**Kết quả mong đợi:**
```
YÊU CẦU 1 (GitOps)    : 3/3 (100%) ✅
YÊU CẦU 2 (SLO+Alert) : 5/5 (100%) ✅
YÊU CẦU 3 (Canary)    : 6/6 (100%) ✅

🎉 HOÀN HẢO! Tất cả yêu cầu đã đáp ứng!
```

**Nếu vẫn fail:** Xem phần Troubleshooting hoặc liên hệ hỗ trợ.

---

### ✅ BƯỚC 5: TEST YÊU CẦU 1 - GITOPS (10 phút)

#### 5.1. Xem hướng dẫn

```powershell
.\quick-test.ps1 1
```

#### 5.2. Test deploy qua Git

```powershell
# 1. Sửa file k8s-api\api.yaml (dòng 27)
# Từ: value: "v3"
# Thành: value: "v4-test"

# 2. Commit và push
git add k8s-api\api.yaml
git commit -m "test: deploy api v4"
git push

# 3. Theo dõi deploy
kubectl argo rollouts get rollout api -n demo -w
# Nhấn Ctrl+C để thoát khi thấy Status: Healthy
```

**Kết quả mong đợi:**
- ArgoCD sync trong ~30 giây
- Rollout hoàn thành trong ~4-5 phút
- Pods chạy version mới: `v4-test`

#### 5.3. Test rollback < 5 phút

```powershell
# Bắt đầu đếm thời gian
$startTime = Get-Date

# 1. Rollback
git revert HEAD --no-edit
git push

# 2. Đợi hoàn thành
kubectl argo rollouts get rollout api -n demo -w
# Nhấn Ctrl+C khi thấy Status: Healthy

# 3. Tính thời gian
$endTime = Get-Date
$duration = ($endTime - $startTime).TotalMinutes
Write-Host "⏱️ Rollback time: $duration minutes" -ForegroundColor Green
```

**Kết quả mong đợi:**
- ✅ Rollback hoàn thành trong < 5 phút
- ✅ Pods quay về version cũ: `v3`

---

### ✅ BƯỚC 6: TEST YÊU CẦU 2 - SLO + ALERT (10 phút)

#### 6.1. Xem hướng dẫn

```powershell
.\quick-test.ps1 2
```

#### 6.2. Deploy bản có lỗi

```powershell
# 1. Sửa file k8s-api\api.yaml (dòng 24)
# Từ: value: "0"
# Thành: value: "0.3"  # 30% lỗi

# 2. Commit và push
git add k8s-api\api.yaml
git commit -m "test: trigger alert with 30% error rate"
git push

# 3. Đợi deploy xong
kubectl argo rollouts get rollout api -n demo -w
```

#### 6.3. Gửi traffic để tạo metrics

```powershell
# Lấy IP của service
$api_ip = kubectl get svc api -n demo -o jsonpath='{.spec.clusterIP}'

# Gửi 200 requests
Write-Host "Gửi traffic đến API..." -ForegroundColor Yellow
for ($i=1; $i -le 200; $i++) {
    try {
        Invoke-RestMethod -Uri "http://${api_ip}:8080/api/data" -Method GET -TimeoutSec 2 | Out-Null
    } catch {
        # Bỏ qua lỗi 500
    }
    if ($i % 20 -eq 0) {
        Write-Host "  Đã gửi $i/200 requests..." -ForegroundColor Gray
    }
    Start-Sleep -Milliseconds 100
}
Write-Host "✅ Hoàn thành gửi traffic" -ForegroundColor Green
```

#### 6.4. Kiểm tra alert trong Prometheus

```powershell
# Mở Prometheus UI
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
```

Mở browser: http://localhost:9090/alerts

**Tìm alert:** `APIHighErrorRate`
- Sau ~2 phút: **PENDING**
- Sau ~4 phút: **FIRING** 🔥

#### 6.5. Kiểm tra email

**Đợi ~3-5 phút**, kiểm tra inbox: `haileab542@gmail.com`

**Email mong đợi:**
- **Subject:** `🚨 [CRITICAL] APIHighErrorRate`
- **Nội dung:**
  - Success rate < 95%
  - Hướng dẫn rollback
  - Link dashboard

**Nếu không nhận được email:** Xem phần Troubleshooting.

---

### ✅ BƯỚC 7: TEST YÊU CẦU 3A - CANARY THÀNH CÔNG (10 phút)

#### 7.1. Xem hướng dẫn

```powershell
.\quick-test.ps1 3
```

#### 7.2. Deploy bản tốt

```powershell
# 1. Sửa file k8s-api\api.yaml
# - Dòng 24: value: "0"          # ERROR_RATE = 0
# - Dòng 27: value: "v5-good"    # VERSION

# 2. Commit và push
git add k8s-api\api.yaml
git commit -m "test: deploy healthy version v5"
git push
```

#### 7.3. Gửi traffic liên tục

**Mở terminal mới** (PowerShell 2), chạy:

```powershell
$api_ip = kubectl get svc api -n demo -o jsonpath='{.spec.clusterIP}'

Write-Host "Gửi traffic liên tục... Nhấn Ctrl+C để dừng" -ForegroundColor Yellow
while ($true) {
    try {
        Invoke-RestMethod -Uri "http://${api_ip}:8080/api/data" -Method GET -TimeoutSec 2 | Out-Null
    } catch {
        # Bỏ qua lỗi
    }
    Start-Sleep -Milliseconds 500
}
```

#### 7.4. Theo dõi Rollout (Terminal 1)

```powershell
kubectl argo rollouts get rollout api -n demo -w
```

**Quan sát:**
```
Step 1/7: setWeight: 25        ✅ (25% traffic)
Step 2/7: pause: 30s           ⏸️ (chờ metrics)
Step 3/7: analysis             🔍 (đo 5 lần)
  ├─ success-rate: ✅ 100%     (pass 5/5)
  ├─ error-rate: ✅ 0%
  └─ request-rate: ✅ > 0.1

Step 4/7: setWeight: 50        ✅ (50% traffic)
Step 5/7: pause: 30s           ⏸️
Step 6/7: analysis             🔍
  └─ All metrics: ✅ Pass

Step 7/7: setWeight: 100       🎉 PROMOTED

Status: ✅ Healthy
Images: w9-api:1 (stable, tag: v5-good)
```

**Kết quả:** Bản tốt được promote lên 100% ✅

---

### ✅ BƯỚC 8: TEST YÊU CẦU 3B - CANARY TỰ ĐỘNG ABORT (10 phút)

#### 8.1. Deploy bản lỗi

```powershell
# 1. Sửa file k8s-api\api.yaml
# - Dòng 24: value: "0.5"        # ERROR_RATE = 50%
# - Dòng 27: value: "v6-bad"     # VERSION

# 2. Commit và push
git add k8s-api\api.yaml
git commit -m "test: deploy bad version v6"
git push
```

#### 8.2. Tiếp tục gửi traffic (Terminal 2)

Script gửi traffic ở Terminal 2 vẫn chạy (hoặc chạy lại nếu đã dừng).

#### 8.3. Theo dõi Rollout (Terminal 1)

```powershell
kubectl argo rollouts get rollout api -n demo -w
```

**Quan sát:**
```
Step 1/7: setWeight: 25        ✅ (25% traffic)
Step 2/7: pause: 30s           ⏸️
Step 3/7: analysis             🔍
  ├─ success-rate: ❌ ~50%     (< 95% → FAIL)
  ├─ error-rate: ❌ ~50%       (> 5% → FAIL)
  └─ Failure count: 2/2        (đạt failureLimit)

🚨 Analysis FAILED → Auto ABORT
⏳ Waiting 30s (abortScaleDownDelaySeconds)
🔄 Scaling down canary pods...

Status: ✅ Healthy (rollback về stable)
Images: w9-api:1 (stable, tag: v5-good)  ← Vẫn là bản cũ!
```

**Kết quả:** Bản lỗi tự động abort, rollback về stable ✅

#### 8.4. Xác nhận không có downtime

```powershell
# Kiểm tra pods
kubectl get pods -n demo -l app=api

# Kết quả: 4 stable pods vẫn chạy, không bị gián đoạn
```

---

## 🎉 HOÀN THÀNH - XÁC NHẬN ĐẠT YÊU CẦU

### Checklist cuối cùng:

```powershell
# Chạy lại script kiểm tra
.\test-requirements.ps1
```

**Kết quả:** 14/14 tests passed (100%) ✅

### Tổng kết test:

| Yêu cầu | Test | Kết quả |
|---------|------|---------|
| **1. GitOps + Rollback < 5'** | ✅ Đã test | Deploy qua Git, rollback < 5 phút |
| **2. SLO + Alert → Email** | ✅ Đã test | Nhận email khi SLO vi phạm |
| **3. Canary tự động** | ✅ Đã test | Bản tốt promote, bản lỗi abort |

---

## 🐛 TROUBLESHOOTING

### ❌ Vấn đề 1: Không nhận được email

**Nguyên nhân:** SMTP configuration sai hoặc chưa được Alertmanager nhận.

**Giải pháp:**

```powershell
# 1. Kiểm tra logs Alertmanager
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager --tail=100 | Select-String "email"

# 2. Kiểm tra AlertmanagerConfig
kubectl get alertmanagerconfig api-email-alerts -n demo -o yaml

# 3. Kiểm tra Secret
kubectl get secret alertmanager-email-secret -n demo -o jsonpath='{.data.password}' | base64 -d
# → Phải hiển thị password đúng

# 4. Restart Alertmanager
kubectl rollout restart statefulset -n monitoring alertmanager-prometheus-kube-prometheus-alertmanager

# 5. Test lại bằng cách trigger alert
```

---

### ❌ Vấn đề 2: Analysis không chạy

**Nguyên nhân:** Prometheus không có metrics hoặc query sai.

**Giải pháp:**

```powershell
# 1. Kiểm tra ServiceMonitor có scrape metrics không
kubectl get servicemonitor api -n demo -o yaml

# 2. Test metrics endpoint
kubectl port-forward -n demo svc/api 8080:8080
# Mở browser: http://localhost:8080/metrics
# Tìm: flask_http_request_total

# 3. Kiểm tra Prometheus có metrics
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Query: flask_http_request_total{app="api"}

# 4. Nếu không có metrics, kiểm tra app có expose /metrics không
kubectl logs -n demo -l app=api --tail=50

# 5. Xem logs AnalysisRun
kubectl get analysisrun -n demo
kubectl describe analysisrun <name> -n demo
```

---

### ❌ Vấn đề 3: Rollout bị Degraded

**Lỗi:** "scaleDownDelaySeconds requires traffic routing"

**Giải pháp:**

```powershell
# Đã fix trong k8s-api\api.yaml, chỉ cần apply lại
kubectl apply -f k8s-api\api.yaml

# Kiểm tra
kubectl argo rollouts get rollout api -n demo
# → Status: Healthy
```

---

### ❌ Vấn đề 4: ArgoCD không sync

**Giải pháp:**

```powershell
# 1. Kiểm tra Application status
kubectl get app api -n argocd -o yaml | Select-String "status" -Context 10

# 2. Force refresh
kubectl patch app api -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# 3. Xem logs ArgoCD
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

---

## 📚 TÀI LIỆU THAM KHẢO

- **TESTING-README.md** - Tổng quan về test
- **TEST-GUIDE.md** - Hướng dẫn chi tiết từng bước
- **test-requirements.ps1** - Script kiểm tra tự động
- **quick-test.ps1** - Script hướng dẫn test nhanh

---

## 📞 HỖ TRỢ

Nếu gặp vấn đề, cung cấp:
1. Output của `.\test-requirements.ps1`
2. Logs: `kubectl logs ...`
3. Screenshot lỗi

---

## 🎬 DEMO VIDEO (Đề xuất)

Ghi lại video demo test để nộp bài:

1. **Phần 1 (5 phút):** Test GitOps + Rollback
2. **Phần 2 (5 phút):** Test Alert + Email
3. **Phần 3 (10 phút):** Test Canary thành công + abort

**Công cụ:** OBS Studio, ShareX, hoặc Windows Game Bar (Win+G)

---

**🎉 Chúc bạn test thành công!**

Nếu hoàn thành tất cả test trên, bạn đã đáp ứng đầy đủ 3 yêu cầu đề bài! 🚀
