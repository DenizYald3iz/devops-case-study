#!/bin/bash
kubeadm join 192.168.56.10:6443   --token abcdef.1234567890abcdef   --discovery-token-ca-cert-hash sha256:c6c280b78d5d1e8a8b4d4c8336702fdc4f6b6eb11b9aec381df1941e122dd698
