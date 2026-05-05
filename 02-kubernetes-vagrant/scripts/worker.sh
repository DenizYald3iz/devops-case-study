#!/bin/bash
set -euo pipefail

# Node zaten cluster'a katılmışsa join'i atla (provision idempotency)
if [ -f /etc/kubernetes/kubelet.conf ]; then
  echo "Node already joined the cluster, skipping join."
  exit 0
fi

# Master'ın join.sh'ı oluşturmasını bekle
echo "Waiting for join.sh from master..."
while [ ! -f /vagrant/join.sh ]; do
  sleep 5
done

bash /vagrant/join.sh