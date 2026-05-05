# 05-monitoring — Prometheus + Grafana Stack

Streamlit uygulamasının CPU ve bellek kullanımını izleyen monitoring stack'i.

## Hızlı Başlangıç

```bash
# Önce uygulamayı başlat (cAdvisor container'ı görebilsin)
cd ../01-docker && docker compose up -d

# Monitoring stack'i başlat
cd ../05-monitoring
docker compose -f docker-compose.monitoring.yml up -d
```

| Servis | URL | Kimlik Bilgisi |
|---|---|---|
| Grafana | http://localhost:3000 | admin / admin123 |
| Prometheus | http://localhost:9090 | — |
| cAdvisor | http://localhost:8080 | — |
| node-exporter | http://localhost:9100/metrics | — |

## Mimari

```
Streamlit Container
        │
   cAdvisor :8080 ──────────────────┐
   (container CPU/mem)              │
                                    ▼
   node-exporter :9100 ──► Prometheus :9090 ──► Grafana :3000
   (host CPU/mem/disk)        │                  Dashboard
                         alerts.yml
                         (HIGH/CRITICAL)
```

## Dosya Yapısı

```
05-monitoring/
├── docker-compose.monitoring.yml
├── prometheus/
│   ├── prometheus.yml          ← scrape config (cadvisor, node-exporter, streamlit)
│   └── alerts.yml              ← 5 alert kuralı
└── grafana/
    ├── provisioning/
    │   ├── datasources/        ← Prometheus otomatik bağlanır
    │   └── dashboards/         ← Dashboard otomatik yüklenir
    └── dashboards/
        └── app-dashboard.json  ← CPU & Memory paneller
```

## İzlenen Metrikler

### Container (cAdvisor)
| Metrik | PromQL |
|---|---|
| CPU kullanımı (%) | `rate(container_cpu_usage_seconds_total{name="streamlit-app"}[5m]) * 100` |
| Bellek kullanımı | `container_memory_usage_bytes{name="streamlit-app"}` |
| Bellek limiti | `container_spec_memory_limit_bytes{name="streamlit-app"}` |

### Host (node-exporter)
| Metrik | PromQL |
|---|---|
| CPU kullanımı (%) | `100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` |
| Kullanılabilir bellek (%) | `node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100` |
| Disk kullanımı (%) | `100 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100)` |

## Alert Kuralları

| Alert | Koşul | Severity |
|---|---|---|
| ContainerHighCPU | container CPU > 80% (2dk) | warning |
| ContainerHighMemory | container bellek > limit'in %80'i (2dk) | warning |
| ContainerDown | streamlit-app container görünmüyor (1dk) | critical |
| HostHighCPU | host CPU > 85% (5dk) | warning |
| HostLowMemory | kullanılabilir bellek < %15 (5dk) | critical |

## Test Komutları

**Prometheus hedeflerinin sağlık kontrolü:**
```bash
curl -s http://localhost:9090/api/v1/targets | python3 -c "
import json,sys; [print(t['labels']['job'], t['health'])
for t in json.load(sys.stdin)['data']['activeTargets']]"
```

**Container bellek sorgusu:**
```bash
curl -s 'http://localhost:9090/api/v1/query?query=container_memory_usage_bytes{name="streamlit-app"}'
```

**Container CPU sorgusu:**
```bash
curl -s 'http://localhost:9090/api/v1/query?query=rate(container_cpu_usage_seconds_total{name="streamlit-app"}[5m])*100'
```

## Durdur

```bash
docker compose -f docker-compose.monitoring.yml down
# Volume'ları da silmek için:
docker compose -f docker-compose.monitoring.yml down -v
```
