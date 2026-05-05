# 03-k8s-deployment

Streamlit uygulamasının Kubernetes üzerinde ayağa kaldırılması. 2 replica, RollingUpdate stratejisi, NodePort üzerinden port 80 erişimi.

## Çalıştırmak

```bash
kubectl apply -f namespace.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

Doğrulama:

```bash
kubectl get all -n case-study
curl http://192.168.56.10/_stcore/health   # 200 dönmeli
```

## Port 80 Meselesi

Casein istediği şey "port 80'e açılsın". Kubernetes'in NodePort mekanizması default olarak 30000-32767 aralığını kullanıyor — 80, 443 gibi sistem portları bu range'in dışında. Yani `nodePort: 80` yazdığınızda API server bunu doğrudan reddediyor. Bu sorunu çözmek için üç farklı yola baktım:

**A — kube-apiserver NodePort range'ini genişletmek** (bu repo'da kullanılan)

`master.sh` içinde kube-apiserver'ın static pod manifest'ine `--service-node-port-range=80-32767` parametresi ekleniyor. Static pod manifest'ini değiştirince kubelet fark ediyor ve apiserver pod'unu otomatik yeniden başlatıyor — elle müdahale gerekmiyor. `vagrant up` bittikten sonra `service.yaml`'daki `nodePort: 80` geçerli oluyor ve cluster hazır.

Trade-off: Bu ayar tüm cluster genelinde geçerli. 80 portunu artık herhangi bir servis alabilir, başka bir namespace'deki yanlış bir NodePort tanımı bu portu kapmış olabilir. Tek tenant, kontrollü bir ortamda sorun değil ama birden fazla ekibin kullandığı bir cluster'da bu aralığı açmak istemezsiniz.

**B — NGINX Ingress Controller** (bonus, `ingress.yaml` olarak ekledim)

Gerçek bir production ortamında kullanacağım yöntem bu. Ingress Controller, cluster'a tek bir LoadBalancer veya NodePort üzerinden giren trafiği host adına veya URL path'ine göre içeride doğru servislere dağıtıyor. Bu repo için NGINX Ingress baremetal kurulumu şöyle:

```bash
# Ingress Controller'ı kur (bir kere yapılır)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/baremetal/deploy.yaml

# Controller ayağa kalkana kadar bekle
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

# Ingress kuralını uygula
kubectl apply -f ingress.yaml
```

`ingress.yaml` ne yapıyor: `streamlit-app` servisinin `8080` portuna gelen tüm HTTP trafiğini `/` path'i üzerinden yönlendiriyor. Controller'ın kendisi 80 portundan dinliyor, dolayısıyla dışarıdan 80'e gelen istek doğrudan uygulamaya ulaşıyor.

Bu yöntemin A'ya göre farkı: Port 80, artık cluster'ın genel bir kaynağı değil — Ingress Controller'ın elinde. Yeni bir servis eklemek istediğinizde `nodePort: 80` için çarpışma riski yok, sadece yeni bir Ingress kuralı yazıyorsunuz. TLS, rate limiting, authentication gibi cross-cutting özellikleri de annotation'larla Controller seviyesinde ekleyebiliyorsunuz.

Trade-off: `vagrant up`'tan sonra ek kurulum adımı gerektiriyor. Demo ortamı için bu fazladan efor yaratıyor.

**C — Host iptables NAT kuralı** (denendi, elendi)

`iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 30080` şeklinde host üzerinde paket yönlendirmesi yapılabilir. Teknik olarak çalışıyor ama VM her yeniden başladığında kurallar siliniyor — `iptables-persistent` kurulmadıkça kalıcı değil. Daha önemlisi, bu kural Vagrantfile'ın dışında, elle çalıştırılması gereken bir komut; kurulumu tekrarlanabilir değil.

**Neden A seçildi?**

Bu repo için kriter netti: `vagrant up` çalıştıktan sonra başka hiçbir komuta gerek kalmadan `curl http://192.168.56.10/` çalışsın. A bunu karşılıyor, B gerektirmiyor, C güvenilir değil. Production'a taşınacak olsa B'ye geçilir — `ingress.yaml` zaten hazır, sadece Controller'ı kurmak kalıyor.

## Trafik Akışı

```
Kullanıcı :80
    │
    │  NodePort (range: 80-32767)
    ▼
Node :80
    │
    │  Service port 8080 → targetPort 8501
    ▼
Pod :8501  (Streamlit)
```

## Güvenlik Notları

`deployment.yaml`'da birkaç şey kasıtlı:

- `runAsUser: 999` — Dockerfile'da `useradd -r -u 999` ile UID sabitlendi, K8s ve container aynı kullanıcıda buluşuyor.
- `readOnlyRootFilesystem: false` — Streamlit `/tmp`'e yazıyor, readonly koyunca uygulama açılmıyor.
- `capabilities: drop: ["ALL"]` — gereksiz sistem çağrılarını kesiyor.
- `maxUnavailable: 0` — rolling update sırasında her zaman 2 replica ayakta kalıyor.

## Dosyalar

| Dosya | İçerik |
|---|---|
| `namespace.yaml` | `case-study` namespace |
| `deployment.yaml` | 2 replica, RollingUpdate, liveness/readiness probe, security context |
| `service.yaml` | NodePort — port 8080, targetPort 8501, nodePort 80 |
| `ingress.yaml` | NGINX Ingress — production alternatifi, bonus |

## Temizlik

```bash
kubectl delete namespace case-study
```
