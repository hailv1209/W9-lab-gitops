# 🔧 KHẮC PHỤC LỖI: Prometheus DNS Not Found

## ❌ Lỗi gặp phải

```
RolloutAborted: Rollout aborted update to revision 4: 
Metric "success-rate" assessed Error due to consecutiveErrors (5) > consecutiveErrorLimit (4): 
"Error Message: Post "http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090/api/v1/query": 
dial tcp: lookup prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local on 10.96.0.10:53: no such host"
```

## 🔍 Nguyên nhân

AnalysisTemplate đang dùng **địa chỉ Prometheus SAI**.

**Sai:** `prometheus-kube-prometheus-prometheus.monitoring`  
**Đúng:** `kube-prometheus-stack-prometheus.monitoring`

## ✅ Cách khắc phục (ĐÃ SỬA)

### Bước 1: Kiểm tra service name thực tế

```powershell
kubectl get svc -n monitoring | Select-String prometheus
```

**Kết quả:**
```
kube-prometheus-stack-prometheus    ClusterIP   10.110.143.19   <none>   9090/TCP,8080/TCP
prometheus-operated                 ClusterIP   None            <none>   9090/TCP
```

→ Service đúng là: **kube-prometheus-stack-prometheus**

### Bước 2: Cập nhật AnalysisTemplate

**File đã được sửa:** `k8s-api/analysis-template.yaml`

Tất cả 3 metrics đã được cập nhật từ:
```yaml
address: http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090
```

Thành:
```yaml
address: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090
```

### Bước 3: Apply và Retry

```powershell
# Apply AnalysisTemplate mới
kubectl apply -f k8s-api\analysis-template.yaml

# Retry rollout đang bị abort
kubectl argo rollouts retry rollout api -n demo
```

### Bước 4: Gửi traffic để test

**Mở terminal mới**, chạy:
```powershell
.\send-traffic.ps1
```

**Terminal chính**, theo dõi rollout:
```powershell
kubectl argo rollouts get rollout api -n demo -w
```

---

## 📊 Kết quả mong đợi

Sau khi sửa, rollout sẽ chạy bình thường:

```
Step 1/7: setWeight: 25        ✅ (25% traffic)
Step 2/7: pause: 30s           ⏸️ (chờ metrics)
Step 3/7: analysis             🔍 (đang đo...)
  ├─ success-rate: Running     ← Không còn lỗi DNS!
  ├─ error-rate: Running
  └─ request-rate: Running
```

---

## 🧪 Test kết nối Prometheus

Nếu vẫn gặp vấn đề, test thủ công:

```powershell
# Test 1: Port-forward Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Test 2: Mở browser
# http://localhost:9090/graph

# Test 3: Query metrics
# flask_http_request_total{app="api"}
```

**Nếu thấy metrics:** ✅ Prometheus hoạt động tốt  
**Nếu không thấy metrics:** ⚠️ Cần kiểm tra ServiceMonitor

---

## 🔍 Kiểm tra ServiceMonitor

```powershell
# Xem ServiceMonitor
kubectl get servicemonitor api -n demo -o yaml

# Kiểm tra Prometheus có scrape metrics không
kubectl port-forward -n demo svc/api 8080:8080
# Mở browser: http://localhost:8080/metrics
```

**Phải thấy metrics:**
```
flask_http_request_total{...} 123
flask_http_request_duration_seconds_bucket{...} 456
```

---

## 📝 Commit thay đổi vào Git

```powershell
# Commit file đã sửa
git add k8s-api\analysis-template.yaml
git commit -m "fix: update Prometheus service name in AnalysisTemplate"
git push
```

**Lưu ý:** ArgoCD sẽ tự động sync và apply thay đổi này.

---

## ✅ Checklist

- [x] Kiểm tra service name Prometheus đúng
- [x] Cập nhật analysis-template.yaml (3 metrics)
- [x] Apply AnalysisTemplate mới
- [x] Retry rollout
- [ ] Gửi traffic bằng send-traffic.ps1
- [ ] Theo dõi rollout hoạt động bình thường
- [ ] Commit và push vào Git

---

## 🎉 Kết luận

Lỗi đã được sửa! Bây giờ:

1. **Chạy script gửi traffic:**
   ```powershell
   .\send-traffic.ps1
   ```

2. **Mở terminal khác, theo dõi rollout:**
   ```powershell
   kubectl argo rollouts get rollout api -n demo -w
   ```

3. **Đợi ~3-4 phút** để rollout hoàn thành:
   - 25% → analysis pass → 50% → analysis pass → 100% ✅

Chúc bạn test thành công! 🚀
