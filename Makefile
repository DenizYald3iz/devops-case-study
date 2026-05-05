.PHONY: help up down logs test clean build \
        monitoring-up monitoring-down monitoring-logs \
        k8s-up k8s-down k8s-status k8s-deploy k8s-clean \
        status

# ── Değişkenler ───────────────────────────────────────────────────────────────
APP_DIR        := 01-docker
MONITORING_DIR := 05-monitoring
K8S_DIR        := 03-k8s-deployment
VAGRANT_DIR    := 02-kubernetes-vagrant
IMAGE_NAME     := streamlit-case-app
IMAGE_TAG      := 1.0.0

# ── Varsayılan hedef ──────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  Kullanım: make <hedef>"
	@echo ""
	@echo "  ── Uygulama (Soru 1) ────────────────────────────────────────"
	@echo "  up              Streamlit uygulamasını başlat"
	@echo "  down            Uygulamayı durdur"
	@echo "  build           Docker image'ı build et"
	@echo "  logs            Uygulama loglarını izle"
	@echo "  test            Health check endpoint'ini test et"
	@echo "  clean           Container, image ve volume temizliği"
	@echo ""
	@echo "  ── Kubernetes Cluster (Soru 2) ──────────────────────────────"
	@echo "  k8s-up          Vagrant cluster'ı ayağa kaldır (~15dk)"
	@echo "  k8s-down        Cluster'ı durdur ve VM'leri sil"
	@echo "  k8s-status      Node ve pod durumunu göster"
	@echo ""
	@echo "  ── K8s Deployment (Soru 3) ──────────────────────────────────"
	@echo "  k8s-deploy      Manifest'leri cluster'a uygula"
	@echo "  k8s-clean       case-study namespace'ini sil"
	@echo ""
	@echo "  ── Monitoring (Soru 5) ──────────────────────────────────────"
	@echo "  monitoring-up   Prometheus + Grafana stack'i başlat"
	@echo "  monitoring-down Monitoring stack'i durdur"
	@echo "  monitoring-logs Monitoring container loglarını izle"
	@echo ""
	@echo "  ── Genel ────────────────────────────────────────────────────"
	@echo "  status          Tüm çalışan container'ları göster"
	@echo ""

# ── Soru 1: Docker ───────────────────────────────────────────────────────────
up:
	@echo ">>> Uygulama başlatılıyor..."
	@[ -f $(APP_DIR)/.env ] || cp $(APP_DIR)/.env.example $(APP_DIR)/.env
	docker compose -f $(APP_DIR)/docker-compose.yml up -d
	@echo ">>> Uygulama: http://localhost:8501"

down:
	docker compose -f $(APP_DIR)/docker-compose.yml down

build:
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) $(APP_DIR)/

logs:
	docker compose -f $(APP_DIR)/docker-compose.yml logs -f

test:
	@echo ">>> Health check..."
	@curl -sf http://localhost:8501/_stcore/health && echo " OK" || echo " HATA: Uygulama çalışmıyor"
	@echo ">>> Non-root user kontrolü..."
	@docker exec streamlit-app whoami 2>/dev/null || echo "Container çalışmıyor"

clean:
	docker compose -f $(APP_DIR)/docker-compose.yml down -v
	docker rmi $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true
	docker image prune -f

# ── Soru 2: Kubernetes / Vagrant ─────────────────────────────────────────────
k8s-up:
	@echo ">>> Vagrant cluster başlatılıyor (ilk kurulum ~15 dakika sürer)..."
	cd $(VAGRANT_DIR) && vagrant up
	@echo ">>> Cluster hazır. KUBECONFIG: $(VAGRANT_DIR)/kubeconfig"
	@echo ">>> export KUBECONFIG=$(CURDIR)/$(VAGRANT_DIR)/kubeconfig"

k8s-down:
	cd $(VAGRANT_DIR) && vagrant destroy -f

k8s-status:
	@export KUBECONFIG=$(CURDIR)/$(VAGRANT_DIR)/kubeconfig && \
	echo "=== NODES ===" && kubectl get nodes -o wide && \
	echo "" && echo "=== PODS (kube-system) ===" && kubectl get pods -n kube-system

# ── Soru 3: K8s Deployment ───────────────────────────────────────────────────
k8s-deploy:
	@export KUBECONFIG=$(CURDIR)/$(VAGRANT_DIR)/kubeconfig && \
	kubectl apply -f $(K8S_DIR)/namespace.yaml && \
	kubectl apply -f $(K8S_DIR)/deployment.yaml && \
	kubectl apply -f $(K8S_DIR)/service.yaml && \
	echo ">>> Deployment uygulandı. Port 80: http://192.168.56.10:80"

k8s-clean:
	@export KUBECONFIG=$(CURDIR)/$(VAGRANT_DIR)/kubeconfig && \
	kubectl delete namespace case-study --ignore-not-found

# ── Soru 5: Monitoring ───────────────────────────────────────────────────────
monitoring-up:
	@echo ">>> Monitoring stack başlatılıyor..."
	@[ -f $(APP_DIR)/.env ] || cp $(APP_DIR)/.env.example $(APP_DIR)/.env
	docker compose -f $(APP_DIR)/docker-compose.yml up -d
	docker compose -f $(MONITORING_DIR)/docker-compose.monitoring.yml up -d
	@echo ""
	@echo ">>> Grafana:    http://localhost:3000  (admin / admin123)"
	@echo ">>> Prometheus: http://localhost:9090"
	@echo ">>> cAdvisor:   http://localhost:8080"

monitoring-down:
	docker compose -f $(MONITORING_DIR)/docker-compose.monitoring.yml down

monitoring-logs:
	docker compose -f $(MONITORING_DIR)/docker-compose.monitoring.yml logs -f

# ── Genel ─────────────────────────────────────────────────────────────────────
status:
	@echo "=== Çalışan container'lar ==="
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
