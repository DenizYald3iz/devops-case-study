#!/bin/bash
set -euo pipefail

# Master'ın join.sh'ı oluşturmasını bekle
echo "Waiting for join.sh from master..."
while [ ! -f /vagrant/join.sh ]; do
  sleep 5
done

bash /vagrant/join.sh