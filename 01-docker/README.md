# 01-docker — Streamlit Bitcoin Price App

Bitcoin fiyat geçmişini görselleştiren Streamlit uygulamasının containerize edilmiş hali.

## Hızlı Başlangıç

```bash
cp .env.example .env
docker compose up -d
```

Uygulama `http://localhost:8501` adresinde çalışır.

## Gereksinimler

- Docker >= 24.x
- Docker Compose >= 2.x

## Dosya Yapısı

| Dosya | Açıklama |
|---|---|
| `Dockerfile` | Multi-stage build, Python 3.12, non-root user |
| `docker-compose.yml` | Servis tanımı, healthcheck, ağ yapılandırması |
| `.env.example` | Ortam değişkenleri şablonu |
| `main.py` | Streamlit uygulama kodu |
| `requirements.txt` | Python bağımlılıkları |
| `.dockerignore` | Build context'ten dışlanan dosyalar |

## Ortam Değişkenleri

| Değişken | Varsayılan | Açıklama |
|---|---|---|
| `APP_VERSION` | `1.0.0` | Image tag'inde kullanılır |
| `STREAMLIT_SERVER_PORT` | `8501` | Streamlit'in dinleyeceği port |

## Test Komutları

**Container durumu:**
```bash
docker ps
docker inspect streamlit-app --format "Health: {{.State.Health.Status}}"
```

**Uygulama sağlık kontrolü:**
```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:8501/_stcore/health
# Beklenen: 200
```

**Non-root user doğrulama:**
```bash
docker exec streamlit-app whoami
# Beklenen: appuser
```

**Log takibi:**
```bash
docker logs -f streamlit-app
```

**Durdur ve temizle:**
```bash
docker compose down
docker rmi streamlit-case-app:1.0.0
```

## Mimari Kararlar

### Multi-stage Build
Builder aşamasında bağımlılıklar kurulur, final imaja yalnızca runtime dosyaları kopyalanır. Geliştirme araçları production imajına taşınmaz.

### Python 3.12
Template'te `python:3.8-slim` kullanılıyordu; Python 3.8 Ekim 2024'te EOL olduğu için 3.12'ye yükseltildi. `requirements.txt` de buna göre güncellendi (detay: `REPORT.md`).

### Non-root User
Container içinde `appuser` sistem kullanıcısıyla çalışılır. Root privilege escalation riski ortadan kalkar.

### Healthcheck
`curl` bağımlılığı eklememek için Python'un stdlib `urllib.request` modülü kullanılır. `start_period: 10s` ile Streamlit'in ayağa kalkması için süre tanınır.

### Port Yönetimi
Port `STREAMLIT_SERVER_PORT` env var üzerinden docker-compose tarafından kontrol edilir. Hardcode yerine dışarıdan override edilebilir yapı tercih edildi.