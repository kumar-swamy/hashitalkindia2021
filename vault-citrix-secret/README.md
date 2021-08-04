

## Enabling KV engine and storing the secret in vault
#-------------
vault secrets enable kv-v2

vault kv put secret/citrix-adc/credential username=<username> password=<password>

vault kv put secret/server-cert/cert cert=@server.crt key=@server.key


#Setting up Kubernetes authentication
-----------------
vault auth enable kubernetes

kubectl apply -f token_cluster_role_binding.yaml

export VAULT_SA_NAME=$(kubectl get sa vault-auth -o jsonpath="{.secrets[*]['name']}")

export SA_JWT_TOKEN=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data.token}" | base64 --decode; echo)

export SA_CA_CRT=$(kubectl get secret $VAULT_SA_NAME -o jsonpath="{.data['ca\.crt']}" | base64 --decode; echo)


vault write auth/kubernetes/config \
issuer="https://kubernetes.default.svc.cluster.local" \
token_reviewer_jwt="$SA_JWT_TOKEN" \
kubernetes_host="https://10.102.33.32:6443" \
kubernetes_ca_cert="$SA_CA_CRT"


# Setting up role and policy
--------------------
vault policy write citrix-adc-kv-ro citrix-adc-kv-ro.hcl

vault write auth/kubernetes/role/cic-vault-example \
bound_service_account_names=cic-k8s-role \
bound_service_account_namespaces=default \
policies=citrix-adc-kv-ro \
ttl=24h

# Installation of vault injector helm chart
--------------------
helm repo add hashicorp https://helm.releases.hashicorp.com

helm install vault hashicorp/vault --set "injector.externalVaultAddr=http://10.102.33.36:8200"

helm status vault

kubectl get pods -l app.kubernetes.io/name=vault-agent-injector


# Installation of Citrix Ingress controller helm chart
----------------------------------------
helm repo add citrix https://citrix.github.io/citrix-helm-charts/

helm install citrix citrix/citrix-ingress-controller -f citrix_values.yaml 

kubectl get pod -l app=citrix-citrix-ingress-controller 

kubectl get pods <pod_name> -o yaml 

kubectl exec -it <pod_name> -c cic -- bash 

cat /etc/citrix/.env

cat /vault/secret/mycert



# deploy Application and Ingress
# -------------------------------------
kubectl apply -f kuard_deployment.yaml

kubectl apply -f kuard_service.yaml

kubectl apply -f minimal_ingress.yaml

# Validate the configuration in VPX
#-------------------------------
ssh vpx

sh ssl vserver k8s-10.102.33.42_443_ssl

sh certkey

# Access the application
curl  -k https://citrixdemo.com



