# DevOps Case Study

Bitcoin fiyat geçmişini görselleştiren Streamlit uygulamasının tam DevOps yaşam döngüsü:
containerization, Kubernetes cluster kurulumu, deployment, CI/CD pipeline ve monitoring.

---

## 30 Saniyede Çalıştır

```bash
git clone https://github.com/DenizYald3iz/devops-case-study && cd devops-case-study
make up           # Streamlit uygulamasını başlat → http://localhost:8501
make monitoring-up  # Prometheus + Grafana başlat → http://localhost:3000
```

---

## Make Komutları

```bash
make help           # Tüm komutları listele

# Soru 1 — Docker
make up             # Streamlit uygulamasını başlat
make down           # Durdur
make build          # Image build et
make test           # Health check + non-root user kontrolü
make logs           # Container loglarını izle
make clean          # Container, image, volume temizliği

# Soru 2 — Kubernetes Cluster
make k8s-up         # Vagrant ile 3-node cluster kur (~15dk)
make k8s-down       # Cluster'ı sil
make k8s-status     # Node ve pod durumu

# Soru 3 — K8s Deployment
make k8s-deploy     # Manifest'leri cluster'a uygula
make k8s-clean      # Namespace'i sil

# Soru 5 — Monitoring
make monitoring-up   # Prometheus + Grafana stack
make monitoring-down # Stack'i durdur
make monitoring-logs # Monitoring logları

# Genel
make status         # Çalışan tüm container'lar
```

---

## Proje Yapısı

```
devops-case-study/
├── 01-docker/              ← Soru 1: Dockerfile + docker-compose
├── 02-kubernetes-vagrant/  ← Soru 2: 3-node K8s cluster
├── 03-k8s-deployment/      ← Soru 3: K8s manifests
├── 04-gitlab-ci/           ← Soru 4: CI/CD pipeline
├── 05-monitoring/          ← Soru 5: Prometheus + Grafana
├── Makefile
├── REPORT.md               ← Tüm kararların gerekçesi
└── ARCHITECTURE.md         ← Mimari diyagramlar
```

---

## Soru 1 — Docker

**Uygulama:** Bitcoin fiyat geçmişi görselleştiren Streamlit uygulaması.

### Nasıl Çalıştırılır

```bash
cd 01-docker
cp .env.example .env
docker compose up -d
# http://localhost:8501
```

### Teknik Kararlar

| Karar | Gerekçe |
|---|---|
| Multi-stage build | Builder araçları production imajına taşınmaz, ~%70 boyut azalması |
| Python 3.12 | Template'teki 3.8 Ekim 2024'te EOL oldu, 3.12'ye yükseltildi |
| Non-root user (UID 999) | Root privilege escalation riski ortadan kalkar |
| Healthcheck (urllib) | `curl` kurmadan stdlib ile sağlık kontrolü |
| Port ENV üzerinden | `STREAMLIT_SERVER_PORT` docker-compose'dan kontrol edilir, hardcode yok |

### Test Sonuçları

```
Health endpoint: HTTP 200 ✅
Container user:  appuser   ✅
Image size:      572 MB    ✅
```

---

## Soru 2 — Kubernetes / Vagrant

**Kurulum:** kubeadm ile 1 master + 2 worker node, tamamen otomatik provisioning.

### Nasıl Çalıştırılır

```bash
cd 02-kubernetes-vagrant
vagrant up          # ~15 dakika
export KUBECONFIG=./kubeconfig
kubectl get nodes
```

### Cluster Topolojisi

| Node | IP | RAM | Rol |
|---|---|---|---|
| k8s-master | 192.168.56.10 | 2 GB | control-plane |
| k8s-worker-1 | 192.168.56.11 | 1.5 GB | worker |
| k8s-worker-2 | 192.168.56.12 | 1.5 GB | worker |

### Teknik Kararlar

| Karar | Gerekçe |
|---|---|
| Calico CNI | NetworkPolicy desteği, Flannel yalnızca temel ağ sağlar |
| Idempotent token | `ttl: 0` ile `vagrant destroy && vagrant up` döngüsünde aynı token geçerli |
| Shared folder join | Master CA hash hesaplayıp `/vagrant/join.sh` üretir, worker'lar okur |
| kubeconfig host'a kopyalama | `vagrant up` sonrası host'tan doğrudan `kubectl` kullanılabilir |

### Test Sonuçları

```
k8s-master    Ready  control-plane  ✅
k8s-worker-1  Ready  worker         ✅
k8s-worker-2  Ready  worker         ✅
Calico pods:  Running (3 node)      ✅
```

---

## Soru 3 — Kubernetes Deployment

**Deployment:** 2 replica Streamlit, NodePort servis, port 80 erişimi.

### Nasıl Çalıştırılır

```bash
# Cluster çalışıyor olmalı (make k8s-up)
make k8s-deploy
curl http://192.168.56.10:80/_stcore/health  # 200 beklenir
```

### Port 80 Sorunu ve Çözümü

NodePort varsayılan aralığı 30000-32767'dir, 80 doğrudan verilemez. Üç yol denendi:

| Yol | Açıklama | Tercih |
|---|---|---|
| **A — kube-apiserver range** | `--service-node-port-range=80-32767`, `master.sh`'da otomatik | **✅ Uygulandı** |
| B — Ingress Controller | Production standardı, `ingress.yaml` olarak eklendi | Bonus |
| C — Host iptables | Teslim alan kişi manuel komut çalıştırır | ❌ Reddedildi |

Çözüm A seçildi: `vagrant up` sonrası sıfır manuel adımla `http://192.168.56.10:80` çalışır.

### Teknik Kararlar

| Karar | Gerekçe |
|---|---|
| `maxUnavailable: 0` | Zero-downtime rolling update |
| `runAsUser: 999` | appuser'ın gerçek sistem UID'si (useradd -r ile atanmış) |
| `readOnlyRootFilesystem: false` | Streamlit /tmp'e yazıyor, true yapılırsa crash |
| `case-study` namespace | `default` namespace izolasyon sağlamaz |

### Test Sonuçları

```
Pods:              2/2 Running          ✅
Service NodePort:  8080:80/TCP          ✅
http://192.168.56.10:80  → HTTP 200    ✅
http://192.168.56.11:80  → HTTP 200    ✅
http://192.168.56.12:80  → HTTP 200    ✅
```

---

## Soru 4 — GitLab CI/CD

**Pipeline:** 6 aşamalı güvenli CI/CD — validate → build → scan → push → deploy → rollback.

### Pipeline Akışı

```
git push (main)
    │
validate ──► build ──► scan ──► push ──► deploy ──► rollback
(hadolint)  (kaniko)  (trivy)  (latest  (kubectl   (kubectl
                               tag)      MANUEL)    undo
                                                    MANUEL)
```

### Gerekli CI/CD Değişkenleri

| Değişken | Nereden |
|---|---|
| `CI_REGISTRY_USER` | GitLab otomatik sağlar |
| `CI_REGISTRY_PASSWORD` | GitLab otomatik sağlar |
| `KUBECONFIG_PROD` | `cat ~/.kube/config \| base64 -w0` → Masked+Protected olarak ekle |

### Teknik Kararlar

| Karar | Gerekçe |
|---|---|
| Kaniko (DinD yerine) | DinD `privileged: true` gerektirir — host kernel'e tam erişim; Kaniko rootless |
| Trivy scan (push öncesi) | Shift-Left Security: açık olan image `latest` tag almaz, production'a gidemez |
| `when: manual` deploy | Continuous Delivery: production çıkışı insan onayına bağlı |
| Rollback stage | Disaster Recovery: GitLab UI'dan tek tıkla `kubectl rollout undo` |
| `rules` (only/except değil) | `only/except` deprecated, `rules` daha okunabilir ve esnek |

---

## Soru 5 — Monitoring

**Stack:** Prometheus + Grafana + cAdvisor + node-exporter, otomatik dashboard provisioning.

### Nasıl Çalıştırılır

```bash
make monitoring-up
# Grafana:    http://localhost:3000  (admin / admin123)
# Prometheus: http://localhost:9090
```

### İzlenen Metrikler

| Kaynak | Metrik |
|---|---|
| cAdvisor | Container CPU, bellek, restart sayısı |
| node-exporter | Host CPU, bellek, disk |

### Alert Kuralları

| Alert | Koşul | Severity |
|---|---|---|
| ContainerHighCPU | CPU > %80 (2dk) | warning |
| ContainerHighMemory | Bellek > limit'in %80'i (2dk) | warning |
| ContainerDown | Container görünmüyor (1dk) | critical |
| HostHighCPU | Host CPU > %85 (5dk) | warning |
| HostLowMemory | Kullanılabilir < %15 (5dk) | critical |

### Test Sonuçları

```
Prometheus:          Healthy                ✅
Grafana:             http://localhost:3000  ✅
cAdvisor:            Up                     ✅
node-exporter:       Up                     ✅
streamlit memory:    31.7 MB                ✅
streamlit CPU:       0.000% (idle)          ✅
```

---

## Gereksinimler

| Araç | Versiyon | Kullanım |
|---|---|---|
| Docker | >= 24.x | Soru 1, 5 |
| Docker Compose | >= 2.x | Soru 1, 5 |
| Vagrant | >= 2.4 | Soru 2, 3 |
| VirtualBox | >= 6.1 | Soru 2, 3 |

---

## Detaylı Dokümantasyon

| Dosya | İçerik |
|---|---|
| `REPORT.md` | Tüm kararların gerekçesi ve trade-off analizi |
| `ARCHITECTURE.md` | Mimari diyagramlar |
| `01-docker/README.md` | Docker detayları |
| `02-kubernetes-vagrant/README.md` | Cluster kurulum detayları |
| `03-k8s-deployment/README.md` | Port 80 çözüm analizi |
| `04-gitlab-ci/README.md` | Pipeline aşamaları ve değişkenler |
| `05-monitoring/README.md` | Metrikler ve alert kuralları |
