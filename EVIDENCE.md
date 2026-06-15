# BÁO CÁO EVIDENCE — LAB GITOPS

## Yêu cầu: Đưa bản mới API ra an toàn & tự bảo vệ

---

## 1. GitOps — Mọi thay đổi qua Git, Rollback < 5 phút

### 1.1. Kiểm tra trạng thái ban đầu

- ArgoCD đã sync các App: `api`, `web`, `be`, `kube-prometheus-stack`

<img width="1666" height="842" alt="image" src="https://github.com/user-attachments/assets/69b12904-c480-446d-a283-739941966c93" />


- Rollout `api` đang ở trạng thái Healthy với image stable

<img width="1623" height="827" alt="image" src="https://github.com/user-attachments/assets/4d396daf-0116-4010-870e-8debdc901a52" />

---

### 1.2. Deploy bản mới qua Git (ArgoCD sync)

- Thay đổi VERSION trong `k8s-api/api.yaml`: `v3` → `v4`

<img width="1603" height="447" alt="image" src="https://github.com/user-attachments/assets/faa1fd31-ca8c-47b2-80b4-6df1161fe111" />


```bash
git add k8s-api/api.yaml
git commit -m "deploy: api v6"
git push
```

- ArgoCD tự động phát hiện thay đổi và sync trong ~30 giây

<img width="545" height="562" alt="image" src="https://github.com/user-attachments/assets/9a26dcc4-67fe-4955-b1af-361aa6a58568" />


---

### 1.3. Rollout chạy Canary → Auto-promote

- Rollout tiến hành canary: 25% → 50% → analysis → 100%

<img width="545" height="562" alt="image" src="https://github.com/user-attachments/assets/7698e466-851d-41ce-9ca2-b6131d224859" />

- Canary analysis **pass** (success rate >= 95%) → promote lên 100%

<img width="679" height="474" alt="image" src="https://github.com/user-attachments/assets/e166f69c-1f21-464d-b965-6424249f9135" />

---

### 1.4. Rollback qua Git < 5 phút

- Revert commit vừa push

```bash
git revert HEAD --no-edit
git push
```

<img width="791" height="586" alt="image" src="https://github.com/user-attachments/assets/ff0fa2e2-4d90-4a1d-8667-8b58b0681273" />

- ArgoCD sync → Rollout hoàn thành trong < 5 phút

<img width="675" height="651" alt="image" src="https://github.com/user-attachments/assets/83d69e21-3b22-457c-96a1-8cbd2f08cea8" />


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

<img width="881" height="163" alt="image" src="https://github.com/user-attachments/assets/1060eac8-ea7c-4243-b073-339746bb8908" />

- Kiểm tra AlertmanagerConfig `api-email-alerts` đã được apply

<img width="955" height="158" alt="image" src="https://github.com/user-attachments/assets/ed64f305-83be-4cdf-ae10-41cc9c95574e" />


### 2.2. Kiểm tra Alert baseline (không có alert)

- Gửi traffic bình thường đến API

[screenshot: terminal — gửi request, success rate ~100%]

- Kiểm tra Prometheus: không có alert nào firing

<img width="1909" height="833" alt="image" src="https://github.com/user-attachments/assets/bf012631-aab4-41bc-a3bb-f188b96dd638" />


### 2.3. Trigger Alert (tạo lỗi 500)

- Deploy bản mới với `ERROR_RATE=0.3` (hoặc chỉnh sửa app để trả lỗi 500)

- Gửi traffic để tạo metrics

- Sau ~2-3 phút, Prometheus Rule đo được success rate < 95%

<img width="1908" height="946" alt="image" src="https://github.com/user-attachments/assets/afb482f5-4974-4c8f-b793-6cc2eaba322e" />

### 2.4. Alert fire & Email được gửi

- **Email nhận được tại inbox**

<img width="1569" height="807" alt="image" src="https://github.com/user-attachments/assets/9cdf5caf-70a1-4a42-8bbe-c2d35f26566e" />

---

## 3. Canary tự động — AnalysisTemplate thay pause tay

### 3.1. Kiểm tra AnalysisTemplate đã apply

<img width="893" height="170" alt="image" src="https://github.com/user-attachments/assets/132b44f1-1fb4-4ed2-8acc-5e8c4e4818c7" />

- Xem nội dung AnalysisTemplate `api-success-rate`

<img width="1445" height="960" alt="image" src="https://github.com/user-attachments/assets/630216df-beef-4a5f-afcf-9febb13b870a" />
<img width="1410" height="653" alt="image" src="https://github.com/user-attachments/assets/b9be2adb-4b3e-4d2b-a05e-070c4960ce38" />


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

