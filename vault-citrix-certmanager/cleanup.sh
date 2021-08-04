#/bin/bash
kubectl delete secret citrixdemo
kubectl delete ingress kuard-ingress
kubectl delete clusterissuer vault-issuer
