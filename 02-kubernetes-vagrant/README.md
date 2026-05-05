# 02-kubernetes-vagrant — 3-Node Kubernetes Cluster

Vagrant + VirtualBox üzerinde kubeadm ile kurulan 1 master + 2 worker Kubernetes cluster'ı.

## Hızlı Başlangıç

```bash
cd 02-kubernetes-vagrant
vagrant up
```

Tüm kurulum otomatik çalışır (~10-15 dakika). Tamamlandıktan sonra:

```bash
export KUBECONFIG=./kubeconfig
kubectl get nodes
```

## Gereksinimler

- Vagrant >= 2.3
- VirtualBox >= 7.0
- 6 GB boş RAM (master: 2 GB × 1, worker: 1.5 GB × 2)
- 20 GB boş disk

## Cluster Topolojisi

| Node | IP | CPU | RAM | Rol |
|---|---|---|---|---|
| k8s-master | 192.168.56.10 | 2 | 2048 MB | control-plane |
| k8s-worker-1 | 192.168.56.11 | 2 | 1536 MB | worker |
| k8s-worker-2 | 192.168.56.12 | 2 | 1536 MB | worker |

## Dosya Yapısı

| Dosya | Açıklama |
|---|---|
| `Vagrantfile` | VM tanımları, ağ ve provisioning |
| `kubeadm-config.yaml` | ClusterConfiguration, InitConfiguration, KubeletConfiguration |
| `scripts/common.sh` | Tüm node'larda çalışan ortak kurulum |
| `scripts/master.sh` | Master init, Calico CNI, join.sh üretimi |
| `scripts/worker.sh` | join.sh üzerinden cluster'a katılım |

## Kurulum Akışı

```
vagrant up
    │
    ├── k8s-master
    │     ├── common.sh   (swap, modül, containerd, kubeadm)
    │     └── master.sh   (kubeadm init → Calico → join.sh → kubeconfig)
    │
    ├── k8s-worker-1
    │     ├── common.sh
    │     └── worker.sh   (join.sh bekle → kubeadm join)
    │
    └── k8s-worker-2
          ├── common.sh
          └── worker.sh
```

## Kullanım

**Node durumu:**
```bash
kubectl get nodes -o wide
```

**Master'a SSH:**
```bash
vagrant ssh k8s-master
```

**Worker'a SSH:**
```bash
vagrant ssh k8s-worker-1
```

**Cluster'ı durdur (VM'leri sil):**
```bash
vagrant destroy -f
```

**Yeniden başlat:**
```bash
vagrant up
```

## Mimari Kararlar

### CNI: Calico
Flannel yerine Calico seçildi. Calico `NetworkPolicy` desteği sunar — pod-to-pod trafik izolasyonu production'da zorunludur. Flannel daha basit ama yalnızca temel ağ bağlantısı sağlar.

### Idempotent Token
`kubeadm-config.yaml` içinde `token: abcdef.1234567890abcdef` ve `ttl: 0` tanımlandı. `vagrant destroy && vagrant up` döngülerinde aynı token geçerli kalır, worker join işlemi tekrar çalışabilir.

### Join Mekanizması
Master, CA hash'i hesaplayarak `/vagrant/join.sh` oluşturur. Worker'lar bu dosyayı `/vagrant` shared folder üzerinden okur. `kubeadm token create` çalıştırılmaz — pre-defined token ile fully idempotent.

### kubeconfig Host'a Kopyalanıyor
`master.sh` sonunda `admin.conf` → `/vagrant/kubeconfig` olarak kopyalanır. `vagrant up` tamamlandıktan sonra host makinede `export KUBECONFIG=./kubeconfig` ile doğrudan `kubectl` kullanılabilir.

## Troubleshooting

**Node NotReady kalıyorsa:**
```bash
kubectl describe node k8s-master
# Calico pod'larının durumuna bak
kubectl get pods -n kube-system
```

**join.sh oluşmadıysa:**
```bash
vagrant ssh k8s-master
sudo cat /var/log/syslog | grep kubeadm
```

**Worker join başarısız olduysa:**
```bash
vagrant ssh k8s-worker-1
sudo kubeadm reset -f
sudo bash /vagrant/join.sh
```