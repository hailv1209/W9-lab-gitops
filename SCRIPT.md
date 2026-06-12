# Script Present cho Mentor

---

Chào anh/chị, em xin trình bày giải pháp **"Đưa bản mới API ra an toàn và tự bảo vệ"**. Bài toán gồm 3 yêu cầu chính.

---

**Yêu cầu 1 — GitOps: Mọi thay đổi qua Git, Rollback dưới 5 phút.**

Em sử dụng ArgoCD làm GitOps engine. Toàn bộ cấu hình nằm trong file `k8s-api/api.yaml` — bao gồm Rollout, Service và ServiceMonitor. Khi developer muốn deploy bản mới, chỉ cần sửa VERSION trong file YAML, rồi `git add`, `git commit` và `git push`. ArgoCD phát hiện thay đổi trong khoảng 30 giây và tự động sync vào cluster. Argo Rollout tiếp nhận và chạy canary theo các bước: chuyển 25% traffic sang bản mới, pause 30 giây, chạy Analysis để đánh giá chất lượng, nếu pass thì lên 50%, pause, đánh giá lần 2, và cuối cùng promote lên 100%. Điểm quan trọng là stable pods luôn chạy song song — nên không có downtime. Khi cần rollback, chỉ cần chạy `git revert HEAD --no-edit` rồi push — tạo ra một commit mới undo thay đổi. ArgoCD nhận biết, sync ngược lại, Rollout hoàn thành rollback trong tổng cộng dưới 5 phút. Không cần access trực tiếp vào cluster, không cần `kubectl rollout undo`.

---

**Yêu cầu 2 — SLO + Alert: Gửi email cá nhân khi chất lượng tụt.**

Em cấu hình PrometheusRule trong file `k8s-api/slo-alert.yaml` để định nghĩa SLO. Alert đầu tiên là `APIHighErrorRate` — Prometheus liên tục đo success rate trong 5 phút, nếu dưới 95% trong 30 giây liên tục thì fire. Alert thứ hai là `APIHighLatency` — đo p95 latency, nếu trên 500ms trong 1 phút thì fire. Metrics được scrape từ Flask app qua ServiceMonitor với label `release: prometheus` — label này rất quan trọng vì nhờ nó mà Prometheus Operator nhận diện được ServiceMonitor. Alert được route qua AlertmanagerConfig, match theo label `app=api`, rồi gửi email qua SMTP của Gmail. Password SMTP được lưu trong Kubernetes Secret tạo bằng kubectl — không bao giờ commit vào Git.

---

**Yêu cầu 3 — Canary tự động: Thay pause tay bằng AnalysisTemplate.**

Trước đây dùng pause tay — người phải ngồi theo dõi rồi approve thủ công, vừa tốn công vừa chủ quan. Em thay bằng AnalysisTemplate trong file `k8s-api/analysis-template.yaml`. Template định nghĩa 2 metrics: success-rate phải từ 95% trở lên, và error-rate phải dưới 5%. Prometheus được hỏi 5 lần, mỗi lần cách 30 giây. Nếu fail 2 lần — tức là `failureLimit: 2` — Rollout sẽ tự động abort. Với bản tốt, success rate ~100%, tất cả 5 lần đo đều pass, Rollout tự promote lên 50% rồi lên 100%. Với bản lỗi — em đã test với endpoint `/api/bug` trả về HTTP 500 — success rate rơi vào khoảng 60%, AnalysisTemplate fail ngay ở bước đầu, Rollout tự abort và quay về bản stable. Không cần bất kỳ can thiệp thủ công nào.

---

**Tóm lại**, cả 3 yêu cầu đều được giải quyết: deploy và rollback hoàn toàn qua Git, giám sát chất lượng bằng SLO và alert email, và canary chạy tự động dựa trên metrics thực tế từ Prometheus. Toàn bộ hệ thống được thiết kế theo nguyên tắc **fail-safe** — khi không chắc chắn, hệ thống sẽ abort thay vì promote bản lỗi. Em đã gặp và xử lý một lỗi DNS thực tế trong quá trình triển khai: service name Prometheus bị nhầm từ `prometheus-kube-prometheus-prometheus` thành đúng là `kube-prometheus-stack-prometheus`. Lỗi này đã được ghi lại trong file `FIX-PROMETHEUS-DNS.md`. Em xin hết ạ.
