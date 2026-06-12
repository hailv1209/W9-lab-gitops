# BÁO CÁO EVIDENCE — LAB GITOPS

## Yêu cầu: Đưa bản mới API ra an toàn & tự bảo vệ

---

## 1. GitOps — Mọi thay đổi qua Git, Rollback < 5 phút

### 1.1. Kiểm tra trạng thái ban đầu

- ArgoCD đã sync các App: `api`, `web`, `be`, `kube-prometheus-stack`

[screenshot: ArgoCD UI — danh sách các App đều Synced & Healthy]

- Rollout `api` đang ở trạng thái Healthy với image stable

[screenshot: kubectl argo rollouts get rollout api -n demo]

---

### 1.2. Deploy bản mới qua Git (ArgoCD sync)

- Thay đổi VERSION trong `k8s-api/api.yaml`: `v5` → `v6`

[screenshot: Git commit trong VS Code / terminal]

```bash
git add k8s-api/api.yaml
git commit -m "deploy: api v6"
git push
```

- ArgoCD tự động phát hiện thay đổi và sync trong ~30 giây

[screenshot: ArgoCD UI — App api chuyển sang trạng thái OutOfSync rồi Syncing]

---

### 1.3. Rollout chạy Canary → Auto-promote

- Rollout tiến hành canary: 25% → 50% → analysis → 100%

[screenshot: kubectl argo rollouts get rollout api -n demo — thấy các bước canary tiến triển]

- Canary analysis **pass** (success rate >= 95%) → promote lên 100%

[screenshot: AnalysisTemplate chạy thành công, success-rate: pass]

---

### 1.4. Rollback qua Git < 5 phút

- Revert commit vừa push

```bash
git revert HEAD --no-edit
git push
```

- Bắt đầu đếm thời gian

[screenshot: terminal — bắt đầu rollback, ghi nhận thời gian]

- ArgoCD sync → Rollout hoàn thành trong < 5 phút

[screenshot: kubectl argo rollouts get rollout api -n demo sau khi rollback hoàn tất]

- Kết quả:

| Hành động | Thời gian |
|-----------|-----------|
| `git revert HEAD && git push` | ~1 phút |
| ArgoCD sync | ~30 giây |
| Rollout hoàn thành | ~2-3 phút |
| **Tổng** | **< 5 phút** |

---

## 2. SLO + Alert → Gửi email khi chất lượng tụt

### 2.1. Kiểm tra PrometheusRule đã apply

- Kiểm tra PrometheusRule `api-slo-alerts` trong namespace `demo`

[screenshot: kubectl get prometheusrule -n demo]

- Kiểm tra AlertmanagerConfig `api-email-alerts` đã được apply

[screenshot: kubectl get alertmanagerconfig -n demo]

### 2.2. Kiểm tra Alert baseline (không có alert)

- Gửi traffic bình thường đến API

[screenshot: terminal — gửi request, success rate ~100%]

- Kiểm tra Prometheus: không có alert nào firing

[screenshot: Prometheus UI — Alerts page, không có alert firing]

### 2.3. Trigger Alert (tạo lỗi 500)

- Deploy bản mới với `ERROR_RATE=0.3` (hoặc chỉnh sửa app để trả lỗi 500)

[screenshot: git commit & push với cấu hình lỗi]

- Gửi traffic để tạo metrics

[screenshot: terminal — gửi ~200 requests]

- Sau ~2-3 phút, Prometheus Rule đo được success rate < 95%

[screenshot: Prometheus UI — query success rate, kết quả < 95%]

### 2.4. Alert fire & Email được gửi

- Alert `APIHighErrorRate` chuyển sang trạng thái **FIRING**

[screenshot: Prometheus UI — Alerts page, APIHighErrorRate = FIRING]

- Kiểm tra Alertmanager logs xác nhận email đã gửi

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager --tail=50
```

[screenshot: logs Alertmanager — thấy dòng gửi email thành công]

- **Email nhận được tại inbox**

[screenshot: Email từ Alertmanager, subject "🚨 [CRITICAL] APIHighErrorRate"]

### 2.5. Nội dung email alert

Email chứa đầy đủ thông tin:

- Alert name: `APIHighErrorRate`
- Severity: `critical`
- Success rate hiện tại: `< 95%`
- Hướng dẫn khắc phục (kiểm tra logs, rollback, dashboard link)

[screenshot: Chi tiết nội dung email alert]

---

## 3. Canary tự động — AnalysisTemplate thay pause tay

### 3.1. Kiểm tra AnalysisTemplate đã apply

[screenshot: kubectl get analysistemplate -n demo]

- Xem nội dung AnalysisTemplate `api-success-rate`

[screenshot: kubectl describe analysistemplate api-success-rate -n demo]

### 3.2. Deploy bản TỐT — Auto-promote

- Deploy version mới (image tốt, không lỗi)

[screenshot: git commit "deploy: api v7-good" && git push]

- Rollout chạy các bước tự động:

  1. Canary 25% → pause 30s
  2. **Analysis** (đo success rate 5 lần)
  3. Pass → Canary 50% → pause 30s
  4. **Analysis** (đo lần 2)
  5. Pass → Promote 100%

[screenshot: kubectl argo rollouts get rollout api -n demo — thấy analysis pass, auto-promote]

### 3.3. Deploy bản LỖI — Auto-abort

- Deploy version mới (image lỗi, trả ~40% lỗi 500)

[screenshot: git commit "deploy: api v8-bad" && git push]

- Rollout chạy canary:

  1. Canary 25% → pause 30s
  2. **Analysis** → Fail (success rate ~60% < 95%)
  3. **Failure count: 2/2** (đạt failureLimit)
  4. → **Auto ABORT**

[screenshot: kubectl argo rollouts get rollout api -n demo — thấy analysis fail, auto-abort]

### 3.4. Xác nhận rollback về bản stable

- Sau khi abort, rollout quay về bản stable (v7-good)

[screenshot: kubectl argo rollouts get rollout api -n demo — Status: Healthy, image: v7-good]

- Không có downtime — stable pods vẫn phục vụ traffic

[screenshot: kubectl get pods -n demo -l app=api — tất cả pods đang Running]

### 3.5. So sánh: Trước vs Sau khi dùng AnalysisTemplate

| | Trước (pause tay) | Sau (AnalysisTemplate) |
|--|--|--|
| Sau 25% | Cần manual pause + approve | Tự chạy Analysis |
| Đánh giá chất lượng | Con người quyết định | Prometheus tự đo |
| Bản lỗi | Cần manual abort | Tự động abort |
| Thời gian rollback | Phụ thuộc con người | < 5 phút tự động |

---

## 4. Tổng kết

| Yêu cầu | Kết quả |
|----------|---------|
| ✅ GitOps — Mọi thay đổi qua Git | ArgoCD sync tự động |
| ✅ Rollback < 5 phút | Rollback qua `git revert` hoàn tất trong ~3-4 phút |
| ✅ SLO + Alert → Email | Alert fire khi success rate < 95%, email gửi về inbox |
| ✅ Canary tự động | AnalysisTemplate đo chất lượng, bản tốt promote, bản lỗi abort |
| ✅ Không có downtime | Stable pods luôn sẵn sàng phục vụ |

---

## 5. Lệnh kiểm tra nhanh

```bash
# Kiểm tra tất cả thành phần
kubectl get all -n demo
kubectl get prometheusrule -n demo
kubectl get alertmanagerconfig -n demo
kubectl get analysistemplate -n demo

# Theo dõi rollout
kubectl argo rollouts get rollout api -n demo --watch

# Kiểm tra alerts
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090
# Mở http://localhost:9090/alerts

# Kiểm tra logs Alertmanager
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager --tail=50
```
