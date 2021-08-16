## Setup vault
export VAULT_ADDR=http://127.0.0.1:8200

## Generate PKI root
----------------------
```
export DOMAIN=citrixdemo.com
```

```
export PKI_ROOT=pki
```

```
vault secrets enable -path="${PKI_ROOT}" pki
vault secrets tune -max-lease-ttl=87600h "${PKI_ROOT}"
```


```
vault write -format=json "${PKI_ROOT}"/root/generate/internal \
common_name="${DOMAIN} CA root" ttl=87600h | tee \
>(jq -r .data.certificate > ca.pem) \
>(jq -r .data.issuing_ca > issuing_ca.pem) \
>(jq -r .data.private_key > ca-key.pem)
```


## Generate PKI intermdiate CA and sign with root CA
----------------------

```
export PKI_INT=pki_int
vault secrets enable -path=${PKI_INT} pki
vault secrets tune -max-lease-ttl=26280h ${PKI_INT}
```

echo "Generate CSR for the intermediate CA"
```
vault write -format=json "${PKI_INT}"/intermediate/generate/internal \
common_name="${DOMAIN} CA intermediate" ttl=26280h | tee \
>(jq -r .data.csr > pki_int.csr) \
>(jq -r .data.private_key > pki_int.pem)
```

```
vault write "${PKI_ROOT}"/config/urls \
       issuing_certificates="${VAULT_ADDR}/v1/${PKI_ROOT}/ca" \
       crl_distribution_points="${VAULT_ADDR}/v1/${PKI_ROOT}/crl"
```


```
vault write -format=json "${PKI_ROOT}"/root/sign-intermediate csr=@pki_int.csr format=pem_bundle ttl=26280h \
        | jq -r '.data.certificate' > intermediate.cert.pem
```

```
vault write "${PKI_INT}"/intermediate/set-signed certificate=@intermediate.cert.pem
```

```
vault write "${PKI_INT}"/config/urls issuing_certificates="${VAULT_ADDR}/v1/${PKI_INT}/ca" crl_distribution_points="${VAULT_ADDR}/v1/${PKI_INT}/crl"
```


## Setting up a role and attach a policy which allows to sign the cert using PKI intermediate for the given domain and max lease period
```
vault write ${PKI_INT}/roles/kube-ingress \
          allowed_domains=${DOMAIN} \
          allow_subdomains=true \
          max_ttl="2160h" \
          require_cn=false \
	      allowed_uri_sans='*.citrixdemo.com
```

----------------------------------------------

## Vault policy to sign the certificate

```
cat <<EOT > pki_int.hcl
path "${PKI_INT}/sign/*" {
      capabilities = ["create","update"]
    }
EOT
```

```
vault policy write kube-allow-sign pki_int.hcl
```

## Vault authentication and policy binding

```
vault auth enable approle
vault write auth/approle/role/kube-role token_ttl=0

vault write auth/approle/role/kube-role policies=kube-allow-sign
```

## get the Approle tokens and pass it to cert manager

```
vault read auth/approle/role/kube-role/role-id
vault write -f auth/approle/role/kube-role/secret-id
```

## Deploy cert manager
```	
helm install cert-manager jetstack/cert-manager   --namespace cert-manager  --create-namespace   --version v1.4.0   --set installCRDs=true
```

## Deploy cert manager resources
```
kubectl apply -f cert-manager-vault-secret.yaml
kubectl apply -f cluster-issuer.yaml
kubectl apply -f certificate.yaml
```


## deploy application and ingress
```
kubectl apply -f kuard_deploy.yaml
kubectl apply -f kuard_service.yaml
kubectl apply -f kuard_ingress.yaml
```

## Verify that Certs are getting generated
```
kubectl get secret citrixdemo
```

## Verify that certs are used by ADC to deliver the application
```
ssh vpx
sh ssl vserver
```
## Verify the rotation of the certificate and new certificate is being used to deliver the application
```
curl --insecure -vvI https://kuard.citrixdemo.com 2>&1 | awk 'BEGIN { cert=0 } /^\* SSL connection/ { cert=1 } /^\*/ { if (cert) print }'
```





