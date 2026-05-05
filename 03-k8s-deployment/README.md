# 03-k8s-deployment — Kubernetes Manifests

Streamlit uygulamasının Kubernetes üzerinde 2 replica olarak çalıştırılması.

## Hızlı Başlangıç

```bash
kubectl apply -f namespace.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

Doğrulama:
```bash
kubectl get all -n case-study
curl http://192.168.56.10:80/_stcore/health  # 200 beklenir
```

## Port Mimarisi

```
Kullanıcı :80
    │
    │  NodePort (range: 80-32767, master.sh ile otomatik ayarlandı)
    ▼
Node :80  (NodePort)
    │
    │  Service port: 8080 → targetPort: 8501
    ▼
Pod :8501    (Streamlit)
```

## Port 80 Tuzağı ve Çözümler

Case "port 80'e açılsın" istiyor. NodePort default range'i **30000-32767** — 80 doğrudan verilemez.

Üç çözüm değerlendirildi:

### Çözüm A — kube-apiserver range genişletme (bu repo'da uygulanan)

`master.sh` kube-apiserver static pod manifest'ine `--service-node-port-range=80-32767`
parametresi ekler. `vagrant up` ile otomatik çalışır, manuel komut gerekmez.

`service.yaml`'da `nodePort: 80` doğrudan kullanılır.

**Dezavantaj:** Production'da tüm node'larda privileged port aralığı açılır. Tek cluster
birden fazla ekip kullanıyorsa başka servisler yanlışlıkla 80'i alabilir.

### Çözüm B — Ingress Controller (bonus, production yolu)

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/baremetal/deploy.yaml
kubectl apply -f ingress.yaml
```

TLS termination, host-based routing, rate limiting gelir. Production standardı budur.
`ingress.yaml` bu repo'ya bonus olarak eklenmiştir.

### Çözüm C — Host iptables (denendi, reddedildi)

Host makinede `sudo iptables` ile 80 → 30080 yönlendirmesi. Case'i teslim alan kişinin
kendi makinesinde komut çalıştırması gerekir — kabul edilemez UX.

## Neden Çözüm A?

| | A (bu repo) | B (Ingress) | C (iptables) |
|---|---|---|---|
| vagrant up sonrası sıfır manuel adım | ✅ | ✅ | ❌ |
| Production-grade | ❌ | ✅ | ❌ |
| Case'e doğrudan uyum | ✅ | ✅ | ✅ |
| Ek bileşen kurulumu | Yok | Ingress Controller | Yok |

Vagrant demo ortamında ek bileşen olmadan `vagrant up` → `curl :80` çalışsın
istendiğinden Çözüm A seçildi. Production'da Çözüm B kullanılır (`ingress.yaml` hazır).

## Dosyalar

| Dosya | Açıklama |
|---|---|
| `namespace.yaml` | `case-study` namespace |
| `deployment.yaml` | 2 replica, RollingUpdate, probe'lar, security context |
| `service.yaml` | NodePort — port:8080, targetPort:8501, nodePort:80 |
| `ingress.yaml` | BONUS — NGINX Ingress, production port 80 çözümü |

## Temizlik

```bash
kubectl delete namespace case-study
```
