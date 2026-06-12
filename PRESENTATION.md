# Đưa bản mới API ra an toàn & tự bảo vệ

**Họ tên: Lê Văn Hải**  
**Lab: GitOps — W9**  
**Mentor review**

---

## Mục lục

1. [Tổng quan bài toán](#1-tổng-quan-bài-toán)
2. [Yêu cầu 1 — GitOps & Rollback](#2-yêu-cầu-1--gitops--rollback)
3. [Yêu cầu 2 — SLO + Alert → Email](#3-yêu-cầu-2--slo--alert--email)
4. [Yêu cầu 3 — Canary tự động](#4-yêu-cầu-3--canary-tự-động)
5. [Kiến trúc tổng hợp](#5-kiến-trúc-tổng-hợp)
6. [Demo & Evidence](#6-demo--evidence)
7. [Q&A — Câu hỏi thường gặp](#7-qa--câu-hỏi-thường-gặp)

---

## 1. Tổng quan bài toán

### 3 yêu cầu cần đạt

| # | Yêu cầu | Mục tiêu |
|---|---------|-----------|
| 1 | **GitOps** | Mọi thay đổi qua Git. Rollback < 5 phút |
| 2 | **SLO + Alert** | 1 SLO + 1 alert fire → gửi email cá nhân |
| 3 | **Canary tự động** | Thay pause tay bằng AnalysisTemplate: bản tốt → 100%, bản lỗi → tự abort |

### Stack công nghệ sử dụng

```
Kubernetes + ArgoCD + Argo Rollouts + kube-prometheus-stack + Alertmanager
```

- **Kubernetes**: Nền tảng container orchestration
- **ArgoCD**: GitOps engine, tự đồng bộ Git → cluster
- **Argo Rollouts**: Quản lý chiến lược deploy (canary, blue-green)
- **Prometheus (kube-prometheus-stack)**: Thu thập metrics từ API
- **Alertmanager**: Gửi alert notification (email)

---

## 2. Yêu cầu 1 — GitOps & Rollback

### 2.1. Bài toán

> Làm sao để **mọi thay đổi** đều được kiểm soát qua Git, và rollback nhanh khi có sự cố?

### 2.2. Giải pháp — Luồng GitOps

```
[DEV] git commit → git push
         │
         ▼
[GIT REMOTE]
         │
         │ ArgoCD sync (~30s)
         ▼
[ArgoCD] nhận diện thay đổi so với cluster
         │
         ▼
[ArgoCD] sync YAML vào namespace demo
         │
         ▼
[Argo Rollout] áp dụng canary (25% → 50% → 100%)
```

### 2.3. Cấu hình — Rollout (`k8s-api/api.yaml`)

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
        - pause:
            duration: 30s
        - analysis:
        - setWeight: 100
```

### 2.4. Cấu hình — Service (`k8s-api/api.yaml`)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: demo
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 8080
      targetPort: http
  selector:
    app: api        # ← Tất cả pods (stable + canary) đều match
```

### 2.5. Deploy bản mới qua Git

```bash
# Bước 1: Sửa VERSION trong k8s-api/api.yaml
#   version: "v7" → version: "v8"

# Bước 2: Commit và push
git add k8s-api/api.yaml
git commit -m "deploy: api v8"
git push

# Bước 3: ArgoCD tự động phát hiện & sync (~30 giây)
# Argo Rollout chạy canary:
#   25% traffic → [Analysis] → 50% → [Analysis] → 100%
```

### 2.6. Rollback < 5 phút

```bash
# Không cần can thiệp vào cluster!
# Chỉ cần revert commit Git cuối
git revert HEAD --no-edit
git push
```

| Hành động | Thời gian |
|-----------|-----------|
| `git revert HEAD && git push` | ~1 phút |
| ArgoCD phát hiện thay đổi | ~30 giây |
| Argo Rollout hoàn thành rollback | ~2-3 phút |
| **Tổng** | **< 5 phút** |

### 2.7. Tại sao an toàn?

```
┌──────────────────────────────────────────────────────┐
│  1. Mọi thay đổi qua Git                            │
│     → Có lịch sử đầy đủ, ai làm gì, khi nào        │
│                                                      │
│  2. ArgoCD sync tự động, không manual kubectl        │
│     → Tránh human error                              │
│                                                      │
│  3. Canary giới hạn rủi ro                          │
│     → Chỉ 25% traffic vào bản mới ban đầu          │
│                                                      │
│  4. Stable pods luôn chạy song song                 │
│     → Không có downtime khi rollback                │
│                                                      │
│  5. Rollback = git revert                           │
│     → Không cần access trực tiếp vào cluster        │
└──────────────────────────────────────────────────────┘
```

---

## 3. Yêu cầu 2 — SLO + Alert → Email

### 3.1. Bài toán

> Làm sao để khi API có vấn đề (error rate tăng), đội phụ trách **tự động nhận email** mà không cần ngồi watch dashboard?

### 3.2. Luồng hoạt động tổng thể

```
[Flask API] ──/metrics──► [Prometheus] ──scrape 15s──► [PrometheusRule]
                                                         │
                                                    đo success rate
                                                         │
                                    (liên tục < 95% trong 30s)
                                                         │
                                                         ▼
                                             [Alert: APIHighErrorRate]
                                                         │
                                                    FIRING
                                                         │
                                                         ▼
                                             [Alertmanager]
                                                (route by app=api)
                                                         │
                                                    emailConfigs
                                                         │
                                                         ▼
                                             📧 Gửi email về inbox
```

### 3.3. Bước 1 — Prometheus scrape metrics (`k8s-api/api.yaml`)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: api
  namespace: demo
  labels:
    release: prometheus        # Quan trọng! Prometheus Operator nhận theo label này
spec:
  selector:
    matchLabels:
      app: api
  endpoints:
    - port: http              # Tên port trong Service
      path: /metrics          # Endpoint Flask expose metrics
      interval: 15s            # Scrape mỗi 15 giây
```

> **Flask app** (`app/app.py`) sử dụng thư viện `prometheus_flask_exporter` — tự động expose `/metrics` endpoint với các metrics:
> - `flask_http_request_total` — đếm request theo status code
> - `flask_http_request_duration_seconds` — histogram latency

### 3.4. Bước 2 — PrometheusRule định nghĩa SLO (`k8s-api/slo-alert.yaml`)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: api-slo-alerts
  namespace: demo
  labels:
    release: prometheus      # Prometheus Operator nhận rule này qua label
spec:
  groups:
    - name: api-slo
      rules:
        # ── Alert 1: Error Rate vượt ngưỡng SLO ──
        - alert: APIHighErrorRate
          expr: |
            (
              sum(rate(flask_http_request_total{app="api", status!~"5.."}[5m]))
              /
              sum(rate(flask_http_request_total{app="api"}[5m]))
            ) < 0.95
          for: 30s            # Fire CHỈ SAU 30s vi phạm liên tục
          labels:
            severity: critical
            team: backend
            slo: availability
          annotations:
            summary: "API Error Rate vượt ngưỡng SLO 95%"
            description: |
              Success rate hiện tại: {{ $value | humanizePercentage }}
              Ngưỡng SLO: 95%

        # ── Alert 2: Latency cao ──
        - alert: APIHighLatency
          expr: |
            histogram_quantile(0.95,
              sum(rate(flask_http_request_duration_seconds_bucket{app="api"}[5m])) by (le)
            ) > 0.5
          for: 1m
          labels:
            severity: warning
```

#### Giải thích PromQL — Alert 1

```
Tử số: sum(rate(flask_http_request_total{status!~"5.."}))    → request THÀNH CÔNG
Mẫu số: sum(rate(flask_http_request_total{}))                 → TỔNG request

rate(..., [5m])  → tính tốc độ trung bình trong 5 phút gần nhất
!~"5.."         → lọc tất cả status code KHÔNG bắt đầu bằng 5 (2xx, 3xx, 4xx)
```

### 3.5. Bước 3 — Alertmanager gửi email (`k8s-api/slo-alert.yaml`)

```yaml
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: api-email-alerts
  namespace: demo
spec:
  route:
    receiver: email-receiver
    matchers:                        # Chỉ nhận alert có label app=api
      - name: app
        value: api
        matchType: "="
  receivers:
    - name: email-receiver
      emailConfigs:
        - to: 'hailevanhai@gmail.com'
          smarthost: 'smtp.gmail.com:587'
          authUsername: 'demeter.web.design.22@gmail.com'
          authPassword:
            name: alertmanager-email-secret   # Secret được tạo riêng bằng kubectl
            key: password
          requireTLS: true
          headers:
            - key: Subject
              value: '🚨 [{{ .GroupLabels.severity }}] {{ .GroupLabels.alertname }}'
```

### 3.6. Bước 4 — Tạo SMTP Secret

> **Không commit password vào Git!**

```bash
# Tạo Gmail App Password trước:
# 1. https://myaccount.google.com/apppasswords
# 2. Tạo App Password cho "Mail"
# 3. Copy password 16 ký tự

# Tạo secret bằng kubectl (không commit vào Git)
kubectl create secret generic alertmanager-email-secret \
  -n demo \
  --from-literal=password='your-16-char-app-password'
```

### 3.7. Tóm tắt 2 alerts

| Alert | SLO | Metric | Ngưỡng | `for` | Severity |
|-------|-----|--------|--------|-------|----------|
| `APIHighErrorRate` | Availability | Success rate 5 phút | < 95% | 30s | **critical** |
| `APIHighLatency` | Latency | p95 latency 5 phút | > 500ms | 1m | warning |

---

## 4. Yêu cầu 3 — Canary tự động

### 4.1. Bài toán

> Trước đây dùng **pause tay** — cần người manually approve sau mỗi step.  
> Làm sao để quá trình này **tự động hoàn toàn**?

### 4.2. Vấn đề với pause tay

| | Pause tay |
|--|-----------|
| ❌ | Cần người ngồi theo dõi liên tục |
| ❌ | Phụ thuộc con người → chủ quan, dễ sai |
| ❌ | Bản lỗi có thể được approve nhầm |
| ❌ | Không phản ánh đúng chất lượng thực tế |

### 4.3. Giải pháp — AnalysisTemplate

```
[Rollout] ──setWeight 25%──► [pause 30s] ──► [AnalysisTemplate]
                                                     │
                                           Prometheus query metrics
                                                     │
                                      success-rate >= 95% ? error-rate < 5% ?
                                                     │
                                     ┌────────────────┴────────────────┐
                                  PASS ✅                            FAIL ❌
                                     │                                   │
                                  50% traffic                      AUTO ABORT
                                     │                                   │
                              [Analysis 2]                        → rollback
                                     │
                                     ▼
                                  100% traffic
```

### 4.4. Cấu hình AnalysisTemplate (`k8s-api/analysis-template.yaml`)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: api-success-rate
  namespace: demo
spec:
  metrics:
    # ── Metric 1: Success Rate >= 95% ──
    - name: success-rate
      interval: 30s           # Mỗi 30s Prometheus được hỏi 1 lần
      count: 5                # Tổng đo 5 lần
      successCondition: result >= 0.95    # >= 95% → pass
      failureLimit: 2         # Fail 2 lần → abort rollout
      consecutiveErrorLimit: 5
      provider:
        prometheus:
          address: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090
          query: |
            scalar(
              sum(rate(flask_http_request_total{status!~"5..", app="api"}[2m]))
              or vector(1)                  # Không có traffic → 1/1 = 100% (pass)
            )
            /
            scalar(
              sum(rate(flask_http_request_total{app="api"}[2m]))
              or vector(1)                  # Không có traffic → 1/1 = 100% (pass)
            )

    # ── Metric 2: Error Rate < 5% ──
    - name: error-rate
      interval: 30s
      count: 5
      successCondition: result < 0.05       # < 5% → pass
      failureLimit: 2
      provider:
        prometheus:
          address: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090
          query: |
            scalar(
              sum(rate(flask_http_request_total{status=~"5..", app="api"}[2m]))
              or vector(0)                  # Không có lỗi → 0/1 = 0% (pass)
            )
            /
            scalar(
              sum(rate(flask_http_request_total{app="api"}[2m]))
              or vector(1)
            )
```

### 4.5. Tích hợp vào Rollout

```yaml
strategy:
  canary:
    steps:
      - setWeight: 25
      - pause:
          duration: 30s              # Chờ traffic ổn định vào canary
      - analysis:                   # ← Thay pause tay bằng Analysis
          templates:
            - templateName: api-success-rate
      - setWeight: 50
      - pause:
          duration: 30s
      - analysis:                   # ← Đánh giá lần 2 trước khi promote
      - setWeight: 100

    # Analysis chạy LIÊN TỤC ở background
    analysis:
      templates:
        - templateName: api-success-rate
      startingStep: 2               # Bắt đầu monitor từ step analysis đầu tiên
                                   # → Nếu fail → abort NGAY LẬP TỨC

    abortScaleDownDelaySeconds: 30  # Chờ 30s rồi mới scale down canary pods
```

### 4.6. Hai kịch bản canary

#### Kịch bản A — Bản TỐT → Auto-promote 100%

```
┌─────────────────────────────────────────────────────────────┐
│  Deploy: api:v8-bad  (success rate thực tế ~60%)           │
│                                                             │
│  Step 1: Canary 25% ──► pause 30s                           │
│            └─► traffic chảy vào bản mới 25%                │
│                                                             │
│  Step 2: Analysis (đo 5 lần × 30s = 2.5 phút)              │
│            ├─ success-rate: 60%  ❌ fail (< 95%)           │
│            └─ error-rate:   40%  ❌ fail (>= 5%)            │
│            → Failure count: 2/2 (đạt failureLimit = 2)      │
│                                                             │
│  → AUTO ABORT 🚨                                            │
│     Rollback về stable (v7) ✅                               │
│     Không cần can thiệp thủ công!                          │
└─────────────────────────────────────────────────────────────┘
```

#### Kịch bản B — Bản LỖI → Auto-abort

```
┌─────────────────────────────────────────────────────────────┐
│  Deploy: api:v8-bad  (success rate thực tế ~60%)           │
│                                                             │
│  Step 1: Canary 25% ──► pause 30s                           │
│            └─► traffic chảy vào bản mới 25%                │
│                                                             │
│  Step 2: Analysis (đo 5 lần × 30s = 2.5 phút)              │
│            ├─ success-rate: 60%  ❌ fail (< 95%)            │
│            └─ error-rate:   40%  ❌ fail (>= 5%)            │
│            → Failure count: 2/2 (đạt failureLimit = 2)      │
│                                                             │
│  → AUTO ABORT 🚨                                            │
│     Rollback về stable (v7) ✅                              │
│     Không cần can thiệp thủ công!                          │
└─────────────────────────────────────────────────────────────┘
```

### 4.7. So sánh đầy đủ

| | Pause tay | AnalysisTemplate |
|--|-----------|-----------------|
| Sau canary 25% | Người manual approve | Prometheus tự đo |
| Ai quyết định | Con người (chủ quan) | Metrics thực tế (khách quan) |
| Sai sót nhận định | Có thể xảy ra | Không |
| Bản lỗi | Cần manual abort | Tự động abort |
| Thời gian rollback | Phụ thuộc người can thiệp | Tự động, < 5 phút |
| Chi phí vận hành | Cần người trực 24/7 | Hoàn toàn tự động |

---

## 5. Kiến trúc tổng hợp

```
  DEVELOPER
    │
    │ git push
    ▼
┌──────────────────┐
│   GIT REMOTE     │
└───────┬──────────┘
        │ ArgoCD sync (~30s)
        ▼
┌──────────────────────────────────────────────────────────┐
│               KUBERNETES CLUSTER (demo ns)              │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │              Argo Rollout (Canary)                  │ │
│  │                                                     │ │
│  │  replicas: 4                                        │ │
│  │  stable pods ────────────────────────────────────── │ │
│  │  canary pods ─── 25% traffic ──► [Analysis]        │ │
│  │                                    │                │ │
│  │                       ✅ pass → 50% → [Analysis]   │ │
│  │                       ❌ fail → AUTO ABORT           │ │
│  └────────────────────────────────────────────────────┘ │
│        │ /metrics (15s scrape)                         │
│        ▼                                                 │
│  ┌────────────────────────────────────────────────────┐ │
│  │         Prometheus (kube-prometheus-stack)          │ │
│  │                                                     │ │
│  │  ServiceMonitor → scrape /metrics                  │ │
│  │  PrometheusRule → APIHighErrorRate                 │ │
│  │                   → APIHighLatency                  │ │
│  └────────────────────────────────────────────────────┘ │
│        │ Alert (app=api)                                │
│        ▼                                                 │
│  ┌────────────────────────────────────────────────────┐ │
│  │          Alertmanager + AlertmanagerConfig           │ │
│  │                                                     │ │
│  │  match: app=api → email-receiver (SMTP Gmail)       │ │
│  │              → 📧 hailevanhai@gmail.com              │ │
│  └────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

---

## 6. Demo & Evidence

### Các file đã tạo

| File | Mục đích | Loại |
|------|----------|------|
| `k8s-api/api.yaml` | Rollout + Service + ServiceMonitor | K8s YAML |
| `k8s-api/analysis-template.yaml` | AnalysisTemplate (success/error rate) | Argo Rollouts CRD |
| `k8s-api/slo-alert.yaml` | PrometheusRule + AlertmanagerConfig | Prometheus CRD |
| `app/app.py` | Flask app expose `/metrics` | Python |

### Lệnh kiểm tra

```bash
# Xem trạng thái rollout (theo dõi real-time)
kubectl argo rollouts get rollout api -n demo --watch

# Xem tất cả resource trong namespace demo
kubectl get all -n demo

# Xem PrometheusRule
kubectl get prometheusrule -n demo

# Xem AlertmanagerConfig
kubectl get alertmanagerconfig -n demo

# Xem AnalysisTemplate
kubectl get analysistemplate api-success-rate -n demo -o yaml

# Mở Prometheus UI (kiểm tra alerts)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090
# → Mở http://localhost:9090/alerts

# Xem logs Alertmanager (xác nhận email đã gửi)
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager --tail=50

# Xem metrics từ API
kubectl port-forward -n demo svc/api 8080
# → Mở http://localhost:8080/metrics
```

---

## 7. Q&A — Câu hỏi thường gặp

---

### Q1: Tại sao chọn ArgoCD + Argo Rollouts thay vì dùng Deployment thông thường?

**A:**

| Tiêu chí | Deployment thường | Argo Rollouts |
|----------|------------------|---------------|
| Chiến lược deploy | Rolling/Recreate | Canary, Blue-Green, Progressive |
| Rollback | Manual `kubectl rollout undo` | Tự động, qua Git |
| Analysis tích hợp | Không có | AnalysisTemplate + Prometheus |
| Visual UI | ArgoCD không thấy chi tiết | Argo Rollouts dashboard |

**Argo Rollouts** mở rộng Kubernetes Deployment với các chiến lược deploy nâng cao, đặc biệt là tích hợp **AnalysisTemplate** — cho phép đánh giá tự động bằng metrics thay vì con người approve.

---

### Q2: Rollback qua `git revert` khác gì `kubectl rollout undo`?

**A:**

| | `git revert && git push` | `kubectl rollout undo` |
|--|------------------------|----------------------|
| **Nơi thay đổi** | Git repository | Kubernetes cluster |
| **ArgoCD nhận biết** | ✅ Có — qua Git | ❌ Không — ArgoCD không biết |
| **Lịch sử Git** | Giữ nguyên lịch sử | Không ảnh hưởng |
| **Audit trail** | ✅ Rõ ràng, ai revert, khi nào | ❌ Không có |
| **Phù hợp production** | ✅ GitOps best practice | Chỉ dùng emergency |

> **GitOps best practice**: Mọi thay đổi vào cluster đều phải qua Git. Dùng `kubectl` trực tiếp phá vỡ nguyên tắc GitOps.

---

### Q3: `for: 30s` trong PrometheusRule nghĩa là gì?

**A:**

```
for: 30s
│
└── Prometheus ĐỢI 30 giây liên tục vi phạm TRƯỚC KHI fire alert
```

**Ví dụ**: Success rate = 94% trong 25 giây → Alert chưa fire  
Success rate = 94% trong 30 giây → Alert FIRE ✅

**Tại sao cần `for`**:
- Tránh alert false-positive do spike tạm thời (VD: GC pause, network blip)
- Chỉ alert khi vấn đề THỰC SỰ kéo dài

---

### Q4: `failureLimit: 2` và `consecutiveErrorLimit: 5` trong AnalysisTemplate khác gì?

**A:**

| Tham số | Ý nghĩa | Trong bài này |
|---------|---------|---------------|
| `failureLimit: 2` | Số lần metric **fail** → Rollout abort | Fail 2 lần → abort |
| `consecutiveErrorLimit: 5` | Số lần Prometheus query **lỗi liên tiếp** → coi như metric fail | Lỗi 5 lần → coi như fail |
| `count: 5` | Tổng số lần Prometheus được hỏi | Hỏi 5 lần |

**Trong bài này**:
- Prometheus hỏi 5 lần, mỗi lần cách 30s → tổng 2.5 phút
- Fail 2 lần → abort rollout
- `consecutiveErrorLimit: 5` → phòng trường hợp Prometheus không trả lời được (VD: network timeout)

---

### Q5: Tại sao success rate query dùng `or vector(1)`?

**A:**

Query gốc (không có `or vector(1)`):
```
sum(rate(...)) / sum(rate(...))
```

**Vấn đề**: Khi **không có traffic** → tử số = 0, mẫu số = 0 → **0/0 = NaN** → Prometheus không so sánh được → metric fail ❌

**Giải pháp**:
```
sum(rate(...)) or vector(1)) / sum(rate(...)) or vector(1))
```

| Trường hợp | Không có `or vector(1)` | Có `or vector(1)` |
|-----------|------------------------|-------------------|
| Có traffic 100% ok | 100/100 = 1.0 ✅ | 1.0 ✅ |
| Có traffic 60% ok | 60/100 = 0.6 ❌ | 0.6 ❌ |
| Không có traffic | 0/0 = NaN → fail ❌ | 1/1 = 1.0 ✅ |

> Khi không có traffic, ta coi đó là **100% success** — vì không có lỗi thực sự, chỉ là chưa có request nào.

---

### Q6: Làm sao để debug khi AnalysisTemplate fail liên tục?

**A:**

**Bước 1**: Kiểm tra Prometheus có metrics không:
```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090

# Mở http://localhost:9090 → Graph
# Query: flask_http_request_total{app="api"}
```

**Bước 2**: Kiểm tra Rollout logs:
```bash
kubectl describe rollout api -n demo
kubectl get analytictemplate api-success-rate -n demo -o yaml
```

**Bước 3**: Kiểm tra lỗi DNS (lỗi thường gặp):
```bash
# Sai: prometheus-kube-prometheus-prometheus.monitoring
# Đúng: kube-prometheus-stack-prometheus.monitoring

# Verify service name:
kubectl get svc -n monitoring | Select-String prometheus
```

**Bước 4**: Gửi traffic để tạo metrics:
```powershell
.\send-traffic.ps1
```

---

### Q7: `abortScaleDownDelaySeconds: 30` có tác dụng gì?

**A:**

Khi rollout abort, thứ tự xảy ra:

```
1. Rollout detect: analysis fail → ABORT
2. Stable pods: tiếp tục phục vụ traffic
3. Canary pods: CHƯA xóa ngay → chờ 30s
4. Sau 30s: canary pods mới bị scale down về 0
```

**Tại sao chờ 30s**:
- **Logging**: Engineer có 30s để `kubectl logs` vào canary pods xem lỗi gì
- **Debug**: Có thể port-forward vào canary pods để reproduce lỗi
- **An toàn**: Đảm bảo traffic đã chuyển hết về stable trước khi xóa canary

---

### Q8: ServiceMonitor `release: prometheus` label có ý nghĩa gì?

**A:**

```
ServiceMonitor (trong namespace demo)
    │
    │ Có label: release: prometheus
    ▼
Prometheus Operator (trong namespace monitoring)
    │
    │ Nhận diện ServiceMonitor nhờ label "release: prometheus"
    │ (không cần selector phức tạp cross-namespace)
    ▼
Prometheus scrape endpoint /metrics của API service
```

> Nếu **thiếu** label `release: prometheus` → Prometheus Operator **không nhận** ServiceMonitor → `/metrics` không được scrape → không có metrics → AnalysisTemplate fail ❌

---

### Q9: Làm sao gửi được email qua Gmail mà không lộ password?

**A:**

```
┌─────────────────────────────────────────────────────┐
│  Gmail App Password                                 │
│                                                     │
│  1. Vào: https://myaccount.google.com/apppasswords │
│  2. Tạo App Password (16 ký tự)                    │
│  3. Lưu vào Kubernetes Secret bằng kubectl        │
│     kubectl create secret generic                   │
│       alertmanager-email-secret                     │
│       -n demo                                       │
│       --from-literal=password='xxxx xxxx xxxx xxxx'│
│                                                     │
│  → Không commit password vào Git!                  │
│  → Không lưu trong YAML file!                      │
└─────────────────────────────────────────────────────┘
```

**Nguyên tắc**: Secret (password, token, API key) **không bao giờ** commit vào Git repository. Chỉ tạo qua `kubectl create secret` hoặc các secret management tools như Vault, Sealed Secrets.

---

### Q10: Nếu Prometheus gặp sự cố thì canary có bị ảnh hưởng không?

**A:**

| Tình huống | Kết quả |
|-----------|---------|
| Prometheus **down** hoàn toàn | AnalysisTemplate không query được → `consecutiveErrorLimit: 5` trigger → coi như metric fail → **abort rollout** (an toàn) |
| Prometheus **chậm** response | Prometheus query timeout (default ~30s) → Prometheus coi như lỗi → abort |
| Prometheus **có metrics nhưng wrong data** | Nếu success rate < 95% → abort (đúng behavior) |

> **Thiết kế an toàn**: Khi không chắc chắn → **abort** (fail safe). Không bao giờ promote bản mới khi không đo lường được chất lượng.

---

### Tổng kết

| Yêu cầu | Giải pháp | Kết quả |
|---------|-----------|---------|
| ✅ GitOps — Mọi thay đổi qua Git | ArgoCD sync Git → cluster | Không manual kubectl |
| ✅ Rollback < 5 phút | `git revert HEAD && git push` | Hoàn thành ~3-4 phút |
| ✅ SLO + Alert → Email | PrometheusRule + AlertmanagerConfig | Email tự động khi error rate > 5% |
| ✅ Canary tự động | AnalysisTemplate + Argo Rollouts | Bản tốt → promote, bản lỗi → abort |
| ✅ Không downtime | Stable pods luôn chạy song song | Zero-downtime deploy |
