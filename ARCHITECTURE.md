# Mimari Diyagramlar — DevOps Case Study

---

## 1. Genel Bakış

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Geliştirici Makinesi                         │
│                                                                     │
│   ┌──────────────┐   git push   ┌─────────────────────────────┐    │
│   │  Source Code │ ──────────►  │         GitLab              │    │
│   │  01-docker/  │              │  ┌────────────────────────┐ │    │
│   │  03-k8s-dep/ │              │  │   CI/CD Pipeline       │ │    │
│   │  04-gitlab/  │              │  │  validate→build→scan   │ │    │
│   │  05-monitor/ │              │  │  →push→deploy→rollback │ │    │
│   └──────────────┘              │  └──────────┬─────────────┘ │    │
│                                 │             │               │    │
│                                 │  ┌──────────▼─────────────┐ │    │
│                                 │  │   Container Registry   │ │    │
│                                 │  │  registry.gitlab.com   │ │    │
│                                 │  └──────────┬─────────────┘ │    │
│                                 └─────────────┼───────────────┘    │
│                                               │ kubectl set image  │
│   ┌───────────────────────────────────────────▼─────────────────┐  │
│   │                  Kubernetes Cluster (Vagrant)                │  │
│   │   192.168.56.10 master  ·  192.168.56.11/12 worker x2       │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │              Monitoring Stack (Docker Compose)              │  │
│   │         Prometheus · Grafana · cAdvisor · node-exporter     │  │
│   └─────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. CI/CD Pipeline Akışı

```
  git push → main
       │
       ▼
┌─────────────┐
│  validate   │  hadolint ile Dockerfile lint
│             │  hata varsa pipeline durur
└──────┬──────┘
       │
       ▼
┌─────────────┐
│    build    │  Kaniko ile rootless image build
│             │  SHA tag ile registry'ye push
│             │  (DinD değil — privileged mod gerekmez)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│    scan     │  Trivy — HIGH/CRITICAL zafiyet taraması
│             │  zafiyet bulunursa pipeline durur
│             │  image asla latest almaz
└──────┬──────┘
       │
       ▼
┌─────────────┐
│    push     │  crane ile SHA tag → latest
│             │  sadece main branch'te çalışır
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   deploy    │  ◄── MANUEL ONAY
│             │  kubectl set image → rolling update
│             │  kubectl rollout status --timeout=5m
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  rollback   │  ◄── MANUEL / ACİL DURUM
│             │  kubectl rollout undo
└─────────────┘
```

---

## 3. Kubernetes Cluster Topolojisi

```
Host Makinesi (192.168.56.1)
│
├── k8s-master  (192.168.56.10)  2 CPU · 2 GB RAM
│   ├── kube-apiserver        ← --service-node-port-range=80-32767
│   ├── kube-controller-manager
│   ├── kube-scheduler
│   ├── etcd
│   └── calico-node
│
├── k8s-worker-1  (192.168.56.11)  2 CPU · 2 GB RAM
│   ├── kubelet
│   ├── containerd
│   ├── calico-node
│   └── streamlit-app pod  (replica 1)
│
└── k8s-worker-2  (192.168.56.12)  2 CPU · 2 GB RAM
    ├── kubelet
    ├── containerd
    ├── calico-node
    └── streamlit-app pod  (replica 2)

Ağ:
  Pod CIDR   : 192.168.0.0/16   (Calico)
  Service CIDR: 10.96.0.0/12
  Node ağı   : 192.168.56.0/24  (VirtualBox host-only)
```

---

## 4. Trafik Akışı — NodePort (Aktif)

```
  Kullanıcı tarayıcısı
        │
        │  HTTP :80
        ▼
  Node IP (192.168.56.10/11/12)
        │
        │  NodePort 80  →  kube-proxy
        ▼
  Service: streamlit-app  (ClusterIP 10.x.x.x)
  port: 8080  →  targetPort: 8501
        │
        │  kube-proxy iptables routing
        ├──────────────────────────────────┐
        ▼                                  ▼
  Pod (worker-1)                    Pod (worker-2)
  :8501 Streamlit                   :8501 Streamlit
```

## 4b. Trafik Akışı — Ingress (Üretim Alternatifi)

```
  Kullanıcı tarayıcısı
        │
        │  HTTP :80
        ▼
  NGINX Ingress Controller  (NodePort 80)
        │
        │  path: /  →  streamlit-app:8080
        ▼
  Service: streamlit-app
  port: 8080  →  targetPort: 8501
        │
        ├──────────────────────────────────┐
        ▼                                  ▼
  Pod (worker-1) :8501            Pod (worker-2) :8501
```

---

## 5. Monitoring Veri Akışı

```
┌─────────────────────────────────────────────────────────┐
│                    Docker Host                          │
│                                                         │
│  ┌─────────────────┐     ┌──────────────────────────┐  │
│  │  streamlit-app  │     │       cAdvisor           │  │
│  │  container      │◄────│  container_cpu_usage_*   │  │
│  │  :8501          │     │  container_memory_*      │  │
│  └─────────────────┘     │  :8080                   │  │
│                           └──────────┬───────────────┘  │
│  ┌─────────────────┐                 │                  │
│  │  node-exporter  │                 │ scrape /15s      │
│  │  node_cpu_*     │                 │                  │
│  │  node_memory_*  │        ┌────────▼─────────┐        │
│  │  node_disk_*    │◄───────│   Prometheus     │        │
│  │  :9100          │ scrape │   :9090          │        │
│  └─────────────────┘ /15s   │   TSDB 15d       │        │
│                           └────────┬─────────┘        │
│                                    │                   │
│                           ┌────────▼─────────┐        │
│                           │    Grafana        │        │
│                           │    :3000          │        │
│                           │  Dashboard:       │        │
│                           │  · Container CPU  │        │
│                           │  · Container Mem  │        │
│                           │  · Host CPU/Mem   │        │
│                           │  · Disk / Uptime  │        │
│                           └───────────────────┘        │
│                                                         │
│  Alert Kuralları (Prometheus rules):                    │
│  · ContainerHighCPU   >80%  2dk  → warning             │
│  · ContainerHighMemory>80%  2dk  → warning             │
│  · ContainerDown      1dk görünmüyor → critical        │
│  · HostHighCPU        >85%  5dk  → warning             │
│  · HostLowMemory      <15%  5dk  → critical            │
└─────────────────────────────────────────────────────────┘
```

---

## 6. Bileşen Envanteri

| Bileşen | Teknoloji | Versiyon | Nerede |
|---|---|---|---|
| Uygulama | Streamlit | 1.32.0 | Docker container |
| Container runtime | containerd | 2.2.3 | K8s node'ları |
| Orchestration | Kubernetes | 1.29.15 | Vagrant VM (3 node) |
| CNI | Calico | 3.27.0 | K8s cluster |
| VM provider | VirtualBox + Vagrant | 6.1 | Geliştirici makinesi |
| CI/CD | GitLab CI | - | GitLab.com |
| Image build | Kaniko | 1.14.0 | GitLab runner |
| Security scan | Trivy | latest | GitLab runner |
| Metrics scrape | Prometheus | 2.51.0 | Docker Compose |
| Container metrics | cAdvisor | 0.49.1 | Docker Compose |
| Host metrics | node-exporter | 1.7.0 | Docker Compose |
| Visualization | Grafana | 10.4.0 | Docker Compose |
