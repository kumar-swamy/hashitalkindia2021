set -x 
source ./myscript.sh
export VAULT_ADDR=http://127.0.0.1:8200
export DOMAIN=citrixdemo.com
export PKI_ROOT=pki
shopt -s expand_aliases
alias echo='{ save_flags="$-"; set +x;} 2> /dev/null; echo_and_restore'
echo_and_restore() {
	builtin echo ""
        builtin echo "$*"
        case "$save_flags" in
         (*x*)  set -x
        esac
}

echo "Enabling PKI secret engine at root path"
vault secrets enable -path="${PKI_ROOT}" pki

echo "setting the MAX TTL for root CA to 10 years" 
vault secrets tune -max-lease-ttl=87600h "${PKI_ROOT}"

echo "Creating root certificate"
vault write -format=json "${PKI_ROOT}"/root/generate/internal \
common_name="${DOMAIN} CA root" ttl=87600h | tee \
>(jq -r .data.certificate > ca.pem) \
>(jq -r .data.issuing_ca > issuing_ca.pem) \
>(jq -r .data.private_key > ca-key.pem)

echo "root CA"
echo "*************************"
cat ca.pem

read -p "Press enter to continue"

echo "Key for Enabling PKI for intermediate CA path"
export PKI_INT=pki_int 
vault secrets enable -path=${PKI_INT} pki

echo "Setting the max TTL for intermediate CA to 3 years"
vault secrets tune -max-lease-ttl=26280h ${PKI_INT}

echo "Generate CSR for the intermediate CA"
vault write -format=json "${PKI_INT}"/intermediate/generate/internal \
common_name="${DOMAIN} CA intermediate" ttl=26280h | tee \
>(jq -r .data.csr > pki_int.csr) \
>(jq -r .data.private_key > pki_int.pem)


echo "Configuring the URL for root CA and CRL"
vault write "${PKI_ROOT}"/config/urls \
       issuing_certificates="${VAULT_ADDR}/v1/${PKI_ROOT}/ca" \
       crl_distribution_points="${VAULT_ADDR}/v1/${PKI_ROOT}/crl"


echo "Sign the CSR using root CA urls"
 vault write -format=json "${PKI_ROOT}"/root/sign-intermediate csr=@pki_int.csr format=pem_bundle ttl=26280h \
        | jq -r '.data.certificate' > intermediate.cert.pem

echo "Intermdiate CA cert"
echo "*************************"
cat intermediate.cert.pem

echo "Add the intermediate Cert back to vault"
vault write "${PKI_INT}"/intermediate/set-signed certificate=@intermediate.cert.pem

echo "set the CA and CRL url for intermediate CA cert"
vault write "${PKI_INT}"/config/urls issuing_certificates="${VAULT_ADDR}/v1/${PKI_INT}/ca" crl_distribution_points="${VAULT_ADDR}/v1/${PKI_INT}/crl"

echo "Intermediate CA is setup and can be used to sign the certificate for ingresses"
echo "URL to access the in: ${VAULT_ADDR}/v1/${PKI_INT}/ca"
read -p "Press enter to continue"

echo "Create a vault role kube-ingress which can be used to sign the certificate. "
echo "kube-ingress role allows certs for domains and subdomains of ${DOMAIN} with a max ttl of 90 days"
vault write ${PKI_INT}/roles/kube-ingress \
          allowed_domains=${DOMAIN} \
          allow_subdomains=true \
          max_ttl="2160h" \
          require_cn=false \
	  allowed_uri_sans='*.citrixdemo.com'
echo "Now you can sign the certificate using ${PKI_INT}/sign/kube-ingress path"

read -p "Press enter to continue"

echo "Create an approle based authentication which can be used as authentication with vault server"
echo "Enable approle based autnetication"
vault auth enable approle

echo "Create an aprole called kube-role"
vault write auth/approle/role/kube-role token_ttl=0

echo "Create a policy kube-allow-sign to allow to create and update intermediate sign endpoint"
cat <<EOT > pki_int.hcl 
path "${PKI_INT}/sign/*" {
      capabilities = ["create","update"]
    }
EOT

vault policy write kube-allow-sign pki_int.hcl

echo "set the policy to approle kube-role"
vault write auth/approle/role/kube-role policies=kube-allow-sign

read -p "Press enter to continue"
echo "get the role id and secret id that is used as token for authentication from the cert-manager"
vault read auth/approle/role/kube-role/role-id
vault write -f auth/approle/role/kube-role/secret-id






