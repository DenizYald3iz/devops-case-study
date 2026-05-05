#!/bin/bash
kubeadm join 192.168.56.10:6443   --token abcdef.1234567890abcdef   --discovery-token-ca-cert-hash sha256:17bfa5fa4f58613584f6a93a9ac78f4e3f56735f8cd00ea3a05371884a8c09df
