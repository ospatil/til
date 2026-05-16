---
layout: ../layouts/GistLayout.astro
tags: [ssl, kubernetes]
---

# OpenSSL - Extract Cert and Key from PFX

Extract certificate and private key from a PFX file (PKCS#12 format) and create a Kubernetes TLS secret.

## Extract Certificate

```bash
openssl pkcs12 -in <CERT_FILE>.pfx -nodes -nokeys -nomac -out domain.crt
```

## Extract Private Key

```bash
# Extract encrypted private key
openssl pkcs12 -in <CERT_FILE>.pfx -nocerts -out domain.enc.key

# Decrypt private key
openssl rsa -in domain.enc.key -outform PEM -out domain.key
```

## View Certificate Details

```bash
openssl x509 -text -noout -in domain.crt
```

## Create Kubernetes TLS Secret

```bash
kubectl create secret tls <SECRET_NAME> \
  -n <NAMESPACE> \
  --key=domain.key \
  --cert=domain.crt \
  --output=yaml \
  --dry-run=client > tls-cert-secret.yaml
```
