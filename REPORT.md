# Teknik Rapor — DevOps Case Study

**Aday:** Deniz YALDIZ  
**Tarih:** Mayıs 2026

---

## Soru 1 — Docker Image

### Ne yaptım

Streamlit uygulamasını çalıştıran bir Docker image'ı oluşturdum. Temel hedefler küçük image boyutu, non-root çalışma ve sağlıklı bir healthcheck mekanizmasıydı.

**Multi-stage build** tercih ettim. `builder` stage'inde Python bağımlılıklarını `pip install --user` ile `/root/.local`'a kuruyorum, final stage'e yalnızca bu dizini kopyalıyorum. Bu sayede `pip`, `setuptools` ve build araçları final image'a taşınmıyor. Tek stage ile karşılaştırıldığında image boyutu anlamlı ölçüde küçülüyor.

**Non-root kullanıcı** için `groupadd -r -g 999 appuser && useradd -r -u 999 -g appuser -m appuser` ile UID/GID sabit olarak 999'a atadım. UID'yi sabitlemek kritik bir detay — `useradd -r` ile otomatik atandığında hangi UID'yi alacağı python:3.12-slim image'ındaki mevcut sistem kullanıcılarına göre değişebilir. Deployment YAML'da `runAsUser: 999` yazıyorum, bu değer container'daki gerçek UID ile örtüşmeli. Sabitlemeden bu garanti verilemiyor.

**Entrypoint** için ayrı bir `entrypoint.sh` yazdım. CMD'yi doğrudan streamlit'e bağlamak yerine bir wrapper kullanmak iki şey sağladı: başlangıçta hangi portta çalıştığını loglamak ve portu `STREAMLIT_SERVER_PORT` environment variable'ından okumak. `--server.port` parametresini de burada veriyorum.

**Healthcheck** `/_stcore/health` endpoint'ini kullanıyor, Streamlit bu endpointi built-in olarak sunuyor.

### Trade-off'lar

`readOnlyRootFilesystem: true` koymak istedim ama Streamlit `/tmp` altına yazıyor — uygulama açılmıyor. `false` olarak bırakmak zorunda kaldım, capabilities drop ile telafi ettim.

`python:3.12-slim` tercihinin sebebi `python:3.12-alpine` ile karşılaştırdığımda bazı paketlerin Alpine'de derlenmesi gerekiyor, bu hem build süresini uzatıyor hem de potansiyel uyumsuzluk yaratıyor. slim ile gelen glibc bu sorunu ortadan kaldırıyor.

---

## Soru 2 — Kubernetes Cluster (Vagrant)

### Ne yaptım

Vagrant + VirtualBox üzerinde 1 master, 2 worker'dan oluşan bir Kubernetes 1.29 cluster'ı kurdum. Tüm kurulum `scripts/common.sh`, `scripts/master.sh`, `scripts/worker.sh` üzerinden otomatize edildi.

**CNI seçimi:** Calico tercih ettim. Flannel kurulum kolaylığı açısından daha basit ama NetworkPolicy desteği yok. Production ortamlarında pod-to-pod trafik kısıtlaması standart bir gereklilik olduğundan Calico daha uygun bir seçim.

**Container runtime:** containerd kullandım, Docker değil. Kubernetes 1.24'ten itibaren dockershim kaldırıldı, containerd doğrudan CRI uyumlu. `SystemdCgroup = true` ayarı zorunlu — aksi halde kubelet ve containerd farklı cgroup driver'ı kullandığında node instable hale geliyor.

**Sabit token ile join:** `kubeadm init`'te önceden tanımlı bir token kullandım. Böylece `master.sh` tamamlanınca join komutu öngörülebilir bir formatta `/vagrant/join.sh`'a yazılabiliyor, worker'lar bu dosyayı bekleyerek join ediyor. Random token ile bu koordinasyon daha karmaşık olurdu.

### Sorunlar ve çözümler

**GPG `/dev/tty` hatası:** `gpg --dearmor` komutu Vagrant'ın non-interactive SSH ortamında `/dev/tty`'yi açmaya çalışıyor, bu device provision bağlantısında mevcut değil. `--batch --yes --no-tty` flag'leri eklenerek çözüldü.

**`vagrant provision` idempotency:** `kubeadm init` ikinci kez çalışınca portlar ve manifest dosyaları zaten mevcut olduğu için hata veriyordu. `/etc/kubernetes/admin.conf` varlığını kontrol ederek init adımını koşullu yaptım. Worker'da aynı şekilde `/etc/kubernetes/kubelet.conf` kontrolü eklendi.

---

## Soru 3 — Kubernetes Deployment

### Ne yaptım

Uygulamayı `case-study` namespace'inde 2 replica olarak deploy ettim. Bileşenler: `namespace.yaml`, `deployment.yaml`, `service.yaml`, bonus olarak `ingress.yaml`.

### Port 80 problemi

NodePort'un default aralığı 30000-32767. Casein istediği port 80 bu aralığın dışında. Üç yolu değerlendirdim:

**A — kube-apiserver range genişletme (seçilen):** `master.sh` içinde static pod manifest'e `--service-node-port-range=80-32767` ekleniyor. `vagrant up` sonrası otomatik devreye giriyor, ek adım gerekmiyor.

*Trade-off:* Bu ayar cluster genelinde geçerli. Başka bir servis yanlışlıkla 80 portunu alabilir. Tek ekip, kontrollü bir demo ortamı için kabul edilebilir ama multi-tenant üretim ortamında kullanılmaz.

**B — Ingress Controller:** Üretim standardı bu. Ingress Controller tek bir entry point'ten gelen trafiği host/path bazında yönlendirir. Port 80 Controller'ın elinde olduğu için namespace çakışması riski yok. `ingress.yaml` bu repo'ya hazır halde eklendi. `vagrant up` sonrası ek kurulum adımı gerektirdiğinden demo için A seçildi.

**C — Host iptables NAT:** Teknik olarak çalışıyor ama VM restart'larında kalıcı değil ve Vagrantfile dışında elle komut gerektiriyor. Tekrarlanabilir değil, elendi.

### Deployment kararları

`maxUnavailable: 0`, `maxSurge: 1` kombinasyonuyla rolling update sırasında her zaman 2 replica ayakta kalıyor. `liveness` probe 30 saniye delay ile başlıyor — Streamlit'in tam açılması bu kadar sürebiliyor, erken probe container'ı gereksiz yere restart ettirirdi.

---

## Soru 4 — GitLab CI/CD Pipeline

### Ne yaptım

6 stage'den oluşan bir pipeline tasarladım: `validate → build → scan → push → deploy → rollback`.

**Kaniko (DinD yerine):** Docker-in-Docker, runner'ın `privileged: true` modunda çalışmasını gerektirir — bu host kernel'e tam erişim anlamına gelir. Kaniko aynı işi userspace'de yapar, root yetkisi ve özel socket erişimi gerekmez. Güvenlik açısından anlamlı bir fark.

**Trivy scan, push'tan önce:** "Shift-Left Security" prensibi. HIGH veya CRITICAL zafiyet içeren bir image `latest` tag almaz, production'a gidemez. Pipeline sırası bunu zorunlu kılar.

**Manuel deploy:** Continuous Deployment değil Continuous Delivery felsefesini benimsedim. Build ve scan otomatik, ama production'a çıkış bir insanın onayına bağlı olmalı. GitLab UI'dan "Run" butonuna basmak bu onay mekanizması.

**`rules` (only/except yerine):** `only/except` GitLab dokümantasyonunda deprecated olarak işaretlendi. `rules` daha esnek — `when: manual`, `if` koşulları ve `changes` filtrelerini aynı blokta tanımlamak mümkün.

**Rollback stage:** Deploy sonrası kritik hata çıkarsa terminal açmadan, GitLab UI'dan tek tıkla `kubectl rollout undo` çalışır. Bu bir "break glass" mekanizması.

**`KUBECONFIG_PROD`:** Cluster kubeconfig'i base64 olarak GitLab'da Masked + Protected variable olarak saklanıyor. Pipeline içinde geçici dosyaya decode ediliyor, job bitince siliniyor. Log'a yazdırılmıyor.

---

## Soru 5 — Monitoring

### Ne yaptım

Prometheus + Grafana + cAdvisor + node-exporter stack'i `docker-compose.monitoring.yml` ile ayağa kaldırdım. Grafana datasource ve dashboard provisioning otomatik — container başlar başlamaz her şey hazır.

**cAdvisor:** Container seviyesi metrikler için. `container_cpu_usage_seconds_total` ve `container_memory_usage_bytes` metrikleri `name="streamlit-app"` label'ı üzerinden uygulamaya özel sorgu yapılabiliyor.

**node-exporter:** Host seviyesi metrikler için. CPU, memory, disk kullanımı burada.

**Dashboard panelleri:** Container CPU %, Container Memory (kullanım + limit), Host CPU gauge, Host Memory Available gauge, Container Last Start, Host Disk kullanımı.

**Alert kuralları:** ContainerHighCPU (>80%, 2dk), ContainerHighMemory (limit'in %80'i, 2dk), ContainerDown (1dk görünmüyor), HostHighCPU (>85%, 5dk), HostLowMemory (<%15 available, 5dk).

### Sorunlar ve çözümler

**`host.docker.internal` Linux'ta çalışmıyor:** Docker Desktop (Mac/Windows) bu hostname'i otomatik çözüyor ama Linux'ta default olarak kayıtlı değil. Prometheus servisine `extra_hosts: ["host.docker.internal:host-gateway"]` ekleyerek çözüldü.

**`/_stcore/metrics` endpoint'i yok:** Streamlit'in built-in Prometheus endpoint'i yok, bu job her scrape'te 404 alıyordu. Job kaldırıldı; container metrikleri zaten cAdvisor üzerinden geliyor.

**1970 tarihi (Container Last Start paneli):** `container_start_time_seconds` saniye cinsinden döner, Grafana'nın `dateTimeAsIso` birimi milisaniye bekler. `* 1000` çarpımıyla düzeltildi.

### Mimari tercih

Zabbix veya custom shell script alternatifleri incelendi. Zabbix daha fazla kurulum gerektiriyor ve case'in odağı bu değil. Custom script sürdürülebilir değil. Prometheus ekosistemi hem container hem host metrikleri için standart haline geldi, Grafana ile görselleştirme production kalitesinde sonuç veriyor.

---

## Genel Değerlendirme

Tüm sorularda ortak bir prensip izlemeye çalıştım: her araç kararını bir trade-off analizi üzerine oturtmak. Docker'da güvenlik vs kolaylık, Kubernetes'te CNI seçimi, CI'da build güvenliği, monitoring'de ekosistem olgunluğu. Demo ortamında bazı kısayollar alındı (NodePort range genişletme gibi), bunların üretim için neden farklı yapılması gerektiği ilgili README'lerde açıklandı.
