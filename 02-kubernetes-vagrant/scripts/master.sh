#!/bin/bash
set -euo pipefail #Error durumlarinda tanimsiz degsiken kullanilirsa veya pipe'lar hatayla karsilasirsa script'in durmasini saglar

MASTER_IP="192.168.56.10"
TOKEN="abcdef.1234567890abcdef"

# ── 1. KUBEADM INIT ───────────────────────────────────────────────────────────
# Cluster zaten kuruluysa init'i atla (provision idempotency)
if [ ! -f /etc/kubernetes/admin.conf ]; then
  kubeadm init --config /vagrant/kubeadm-config.yaml
else
  echo "kubeadm already initialized, skipping init."
fi

# ── 2. KUBECONFIG ─────────────────────────────────────────────────────────────
mkdir -p /home/vagrant/.kube
cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube

export KUBECONFIG=/etc/kubernetes/admin.conf

# ── 3. NODEPORT RANGE GENİŞLET (80 portuna izin ver) ─────────────────────────
# Varsayılan: 30000-32767. Case port 80 istediği için range genişletildi.
# Production'da tercih edilmez (ingress.yaml production alternatifidir).
if ! grep -q 'service-node-port-range' /etc/kubernetes/manifests/kube-apiserver.yaml; then
  sed -i '/--service-cluster-ip-range/i\    - --service-node-port-range=80-32767' \
    /etc/kubernetes/manifests/kube-apiserver.yaml
  echo "Waiting for API server to restart with new NodePort range..."
  sleep 10
fi

until kubectl get nodes &>/dev/null; do sleep 3; done
echo "API server ready."

# ── 4. CNI — CALICO ───────────────────────────────────────────────────────────
# Calico: NetworkPolicy desteği ve enterprise ekosistemi için tercih edildi
# Pod CIDR: 192.168.0.0/16 (kubeadm-config.yaml ile eşleşmeli)
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# ── 5. JOIN KOMUTU — /vagrant/join.sh ────────────────────────────────────────
# Pre-defined token + CA hash ile idempotent join script'i oluştur
CERT_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt \
  | openssl rsa -pubin -outform der 2>/dev/null \
  | openssl dgst -sha256 -hex \
  | sed 's/^.* //')

cat > /vagrant/join.sh <<EOF
#!/bin/bash
kubeadm join ${MASTER_IP}:6443 \
  --token ${TOKEN} \
  --discovery-token-ca-cert-hash sha256:${CERT_HASH}
EOF

chmod +x /vagrant/join.sh

# ── 6. KUBECONFIG'İ HOST'A KOPYALA (BONUS) ────────────────────────────────────
# vagrant up sonrası host'tan: export KUBECONFIG=./kubeconfig && kubectl get nodes
cp /etc/kubernetes/admin.conf /vagrant/kubeconfig
chmod 644 /vagrant/kubeconfig
