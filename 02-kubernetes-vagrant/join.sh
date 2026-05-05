#!/bin/bash
kubeadm join 192.168.56.10:6443   --token abcdef.1234567890abcdef   --discovery-token-ca-cert-hash sha256:0a43217383f6e1f7c7b84312c61fc4557d9fb31c7e1167226d04c62688060255
