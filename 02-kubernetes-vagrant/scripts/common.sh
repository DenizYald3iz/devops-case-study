#!/bin/bash
set -euo pipefail

# ── 1. SWAP ──────────────────────────────────────────────────────────────────
swapoff -a
sed -i '/swap/d' /etc/fstab
# K8s, swap'in kapalı olmasını gerektirir. Swap açık kalırsa, kubelet düzgün çalışmaz ve düğüm "NotReady" durumuna geçer.

# ── 2. KERNEL MODÜLLERİ ──────────────────────────────────────────────────────
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter
# Kubernetes için gerekli kernel modüllerini (overlay: container filesystem, br_netfilter: pod network trafiğinin iptables tarafından yönetilmesi)
# hem kalıcı (reboot sonrası otomatik yüklensin) hem de anlık (hemen aktif olsun) olacak şekilde ayarlar.

# ── 3. SYSCTL ─────────────────────────────────────────────────────────────────
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

#Pod’lar genelde bridge üzerinden konuşur
#Kubernetes (kube-proxy) iptables kurallarıyla Service routing yaparken, bu kuralların bridge üzerinden geçen trafiğe de uygulanması gerekir. Bu nedenle, net.bridge.bridge-nf-call-iptables ve net.bridge.bridge-nf-call-ip6tables değerlerini 1 yaparak, iptables kurallarının bridge üzerinden geçen IPv4 ve IPv6 trafiğine uygulanmasını sağlarız.
# ── 4. /etc/hosts ─────────────────────────────────────────────────────────────
cat >> /etc/hosts <<EOF
192.168.56.10 k8s-master
192.168.56.11 k8s-worker-1
192.168.56.12 k8s-worker-2
EOF

# ── 5. CONTAINERD ─────────────────────────────────────────────────────────────
apt-get update -qq
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --batch --yes --no-tty --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y containerd.io

# SystemdCgroup = true — kubeadm 1.22+ zorunlu
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml #iki farklı yönetici aynı CPU'yu kontrol etmeye çalışıp çakışır (cgroup conflict). Bu ayar sistemi tek bir otoriteye (systemd) bağlar.

systemctl restart containerd
systemctl enable containerd

# ── 6. KUBEADM / KUBELET / KUBECTL ───────────────────────────────────────────
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
  | gpg --batch --yes --no-tty --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" > /etc/apt/sources.list.d/kubernetes.list

apt-get update -qq
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet