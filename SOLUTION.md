# Giải pháp: Đưa bản mới API ra an toàn & tự bảo vệ

## Tổng quan

Mục tiêu xây dựng một pipeline deploy tự động đảm bảo: **an toàn qua GitOps**, **giám sát qua SLO + Alert**, và **tự phục hồi qua Canary thông minh**.

---

## 1. GitOps — Deploy & Rollback qua Git

### Bài toán
Làm sao để mọi thay đổi đều được kiểm soát qua Git, và rollback nhanh chóng khi có sự cố?

### Giải pháp

#### Cơ chế hoạt động

```
[DEV] → git commit → git push → [GIT REMOTE]
                                    ↓
                         [ArgoCD] tự phát hiện thay đổi (~30s)
                                    ↓
                         [ArgoCD] sync vào cluster
                                    ↓
                         [Rollout] áp dụng thay đổi (canary)
```

#### Cấu hình Rollout — `k8s-api/api.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: api
  namespace: demo
spec:
  replicas: 4
  strategy:
    canary:
      steps:
        - setWeight: 25
        - pause:
            duration: 30s
        - analysis:
            templates:
              - templateName: api-success-rate
        - setWeight: 50
        ...
```

#### Luồng deploy

1. **Thay đổi VERSION trong `k8s-api/api.yaml`**: `v7` → `v8`
2. **Commit và push**:
   ```bash
   git add k8s-api/api.yaml
   git commit -m "deploy: api v8"
   git push
   ```
3. **ArgoCD phát hiện thay đổi**: Tự động sync trong ~30 giây
4. **Rollout chạy canary**: 25% → 50% → 100% (hoặc abort nếu lỗi)

#### Rollback nhanh

```bash
# Revert commit cuối — tạo commit mới undo thay đổi
git revert HEAD --no-edit
git push
```

| Hành động | Thời gian |
|-----------|-----------|
| `git revert HEAD && git push` | ~1 phút |
| ArgoCD sync | ~30 giây |
| Rollout hoàn thành | ~2-3 phút |
| **Tổng** | **< 5 phút** |

### Tại sao an toàn?

- **Mọi thay đổi đều qua Git**: lịch sử đầy đủ, ai làm gì, khi nào
- **Rollback = revert commit**: không cần can thiệp thủ công vào cluster
- **Canary giới hạn rủi ro**: chỉ 25% traffic vào bản mới trước khi đánh giá
- **Stable pods không bị ảnh hưởng**: luôn có bản cũ phục vụ

---

## 2. SLO + Alert — Giám sát & gửi email khi chất lượng tụt

### Bài toán
Làm sao để khi API có vấn đề (error rate tăng, latency cao), đội phụ trách **tự động nhận được email thông báo** mà không cần ngồi watch dashboard?

### Giải pháp

#### PrometheusRule định nghĩa SLO — `k8s-api/slo-alert.yaml`

```yaml
- alert: APIHighErrorRate
  expr: |
    (
      sum(rate(flask_http_request_total{app="api", status!~"5.."}[5m]))
      /
      sum(rate(flask_http_request_total{app="api"}[5m]))
    ) < 0.95
  for: 30s                        # Fire sau 30s vi phạm liên tục
  labels:
    severity: critical
    team: backend
    slo: availability
```

#### AlertmanagerConfig gửi email

```yaml
receivers:
  - name: email-receiver
    emailConfigs:
      - to: 'hailevanhai@gmail.com'
        smarthost: 'smtp.gmail.com:587'
        authUsername: 'demeter.web.design.22@gmail.com'
        authPassword:
          name: alertmanager-email-secret
          key: password
        requireTLS: true
        headers:
          - key: Subject
            value: '🚨 [{{ .GroupLabels.severity | toUpper }}] {{ .GroupLabels.alertname }}'
```

#### Luồng hoạt động

```
[API /metrics] → Prometheus scrape (15s) → [PrometheusRule] đo success rate
                                                    ↓
                                    (success rate < 95% liên tục 30s)
                                                    ↓
                                        [Alert: APIHighErrorRate] FIRING
                                                    ↓
                                          [Alertmanager] nhận alert
                                                    ↓
                                          [SMTP] gửi email về inbox
```

#### 2 alerts được định nghĩa

| Alert | SLO | Ngưỡng | Severity |
|-------|-----|--------|----------|
| `APIHighErrorRate` | Availability | Success rate < 95% trong 5 phút | critical |
| `APIHighLatency` | Latency | p95 > 500ms trong 5 phút | warning |

#### Cấu hình Prometheus scrape — ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: api
  namespace: demo
  labels:
    release: prometheus          # Match Prometheus Operator
spec:
  selector:
    matchLabels:
      app: api
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

#### Lưu ý quan trọng: Fix lỗi DNS Prometheus

Trong quá trình triển khai, gặp lỗi AnalysisTemplate không truy cập được Prometheus:

```
dial tcp: lookup prometheus-kube-prometheus-prometheus.monitoring.svc... no such host
```

**Nguyên nhân**: Tên service Prometheus bị nhầm.

| | Sai | Đúng |
|--|-----|------|
| Service name | `prometheus-kube-prometheus-prometheus` | `kube-prometheus-stack-prometheus` |
| Namespace | monitoring | monitoring |

**Đã sửa** trong `k8s-api/analysis-template.yaml` — đổi address thành `http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090`.

---

## 3. Canary tự động — AnalysisTemplate thay pause tay

### Bài toán
Trước đây dùng **pause tay** sau mỗi canary step — cần người manually approve. Làm sao để quá trình này **tự động hoàn toàn**: bản tốt → promote, bản lỗi → abort.

### Giải pháp

#### AnalysisTemplate định nghĩa metrics đánh giá — `k8s-api/analysis-template.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: api-success-rate
  namespace: demo
spec:
  metrics:
    # Metric 1: Success Rate >= 95%
    - name: success-rate
      interval: 30s
      count: 5              # Đo 5 lần
      successCondition: result >= 0.95
      failureLimit: 2      # Fail 2 lần → abort
      provider:
        prometheus:
          address: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090
          query: |
            scalar(
              sum(rate(flask_http_request_total{status!~"5..", app="api"}[2m]))
              or vector(1)
            )
            /
            scalar(
              sum(rate(flask_http_request_total{app="api"}[2m]))
              or vector(1)
            )

    # Metric 2: Error Rate < 5%
    - name: error-rate
      interval: 30s
      count: 5
      successCondition: result < 0.05
      failureLimit: 2
      ...
```

#### Cấu hình Rollout tích hợp AnalysisTemplate

```yaml
strategy:
  canary:
    steps:
      - setWeight: 25                    # Bước 1: 25% traffic
      - pause:
          duration: 30s                 # Chờ metrics ổn định
      - analysis:                       # Bước 2: Tự đánh giá
          templates:
            - templateName: api-success-rate
      - setWeight: 50                   # Bước 3: Pass → 50%
      - pause:
          duration: 30s
      - analysis:                       # Bước 4: Đánh giá lần 2
      - setWeight: 100                  # Bước 5: Pass → 100%
    
    # Auto abort khi analysis fail
    analysis:
      templates:
        - templateName: api-success-rate
      startingStep: 2                   # Bắt đầu từ step analysis đầu
    
    # Scale down canary sau khi abort
    abortScaleDownDelaySeconds: 30
```

#### Luồng canary tự động

```
┌─────────────────────────────────────────────────────────────┐
│  Deploy bản TỐT (success rate ~100%)                       │
│                                                             │
│  Step 1: Canary 25% → pause 30s                             │
│  Step 2: Analysis (đo 5 lần, mỗi lần 30s)                   │
│           ├─ success-rate: 100%  ✅ pass (>= 95%)          │
│           └─ error-rate:   0%    ✅ pass (< 5%)             │
│  Step 3: setWeight 50%                                      │
│  Step 4: Analysis lần 2                                     │
│           ├─ success-rate: 100%  ✅ pass                    │
│           └─ error-rate:   0%    ✅ pass                    │
│  Step 5: setWeight 100% → Promote hoàn tất ✅               │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Deploy bản LỖI (success rate ~60%, có ~40% lỗi 500)       │
│                                                             │
│  Step 1: Canary 25% → pause 30s                            │
│  Step 2: Analysis (đo 5 lần)                                │
│           ├─ success-rate: 60%  ❌ fail (< 95%)            │
│           └─ error-rate:   40%  ❌ fail (>= 5%)            │
│           → Failure count: 2/2 (đạt failureLimit)          │
│  → AUTO ABORT → Rollback về bản stable ✅                  │
│     (abortScaleDownDelaySeconds: 30s)                       │
└─────────────────────────────────────────────────────────────┘
```

#### So sánh: Trước vs Sau

| | Trước (pause tay) | Sau (AnalysisTemplate) |
|--|---|---|
| Sau canary 25% | Cần người manual approve | Tự chạy Analysis |
| Đánh giá chất lượng | Con người quyết định (subjective) | Prometheus tự đo (objective) |
| Bản lỗi phát hiện | Phụ thuộc con người nhận ra | Tự động abort khi metrics vi phạm |
| Thời gian rollback | Phụ thuộc tốc độ người can thiệp | Tự động, < 5 phút |
| Sai sót con người | Có thể approve nhầm bản lỗi | Không, dựa trên metrics thực tế |

---

## Tổng kết kiến trúc

```
┌──────────────────────────────────────────────────────────────┐
│                        DEVELOPER                              │
│                  git commit / git revert                      │
└──────────────────────┬───────────────────────────────────────┘
                       │ push
                       ▼
┌──────────────────────────────────────────────────────────────┐
│                       GIT REMOTE                              │
└──────────────────────┬───────────────────────────────────────┘
                       │ ArgoCD sync (~30s)
                       ▼
┌──────────────────────────────────────────────────────────────┐
│                    KUBERNETES CLUSTER                        │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐     │
│  │              ArgoCD Rollout (Canary)                │     │
│  │                                                     │     │
│  │  25% → [Analysis] → 50% → [Analysis] → 100%        │     │
│  │          ✅ pass              ✅ pass               │     │
│  │          ❌ abort             ❌ abort → rollback   │     │
│  └─────────────────────────────────────────────────────┘     │
│                          │ metrics (15s scrape)               │
│                          ▼                                    │
│  ┌─────────────────────────────────────────────────────┐     │
│  │        Prometheus (kube-prometheus-stack)          │     │
│  │                                                     │     │
│  │  PrometheusRule: đo success rate vs SLO 95%        │     │
│  │  Alert: APIHighErrorRate  (critical)               │     │
│  │  Alert: APIHighLatency    (warning)                │     │
│  └─────────────────────────────────────────────────────┘     │
│                          │ alert                             │
│                          ▼                                    │
│  ┌─────────────────────────────────────────────────────┐     │
│  │          Alertmanager (AlertmanagerConfig)          │     │
│  │                                                     │     │
│  │  Match: app=api  →  email-receiver                  │     │
│  │  SMTP (Gmail) → 📧 hailevanhai@gmail.com            │     │
│  └─────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────┘
```

---

## Các file đã tạo/sửa

| File | Mục đích |
|------|----------|
| `k8s-api/api.yaml` | Rollout + Service + ServiceMonitor |
| `k8s-api/analysis-template.yaml` | AnalysisTemplate đo success/error rate |
| `k8s-api/slo-alert.yaml` | PrometheusRule + AlertmanagerConfig + SMTP secret |
| `app/app.py` | Flask app với Prometheus metrics endpoint |

---

## Lệnh kiểm tra nhanh

```bash
# Xem trạng thái rollout
kubectl argo rollouts get rollout api -n demo --watch

# Xem AnalysisTemplate
kubectl get analysistemplate api-success-rate -n demo -o yaml

# Xem Prometheus alerts (port-forward trước)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090
# Mở: http://localhost:9090/alerts

# Xem Alertmanager logs
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager --tail=50

# Xem Prometheus metrics từ API
kubectl port-forward -n demo svc/api 8080
# Mở: http://localhost:8080/metrics
```
