---
layout: ../layouts/GistLayout.astro
tags: [ssl]
---

# OpenSSL - convert pfx to crt and key files

```bash
# extracting the certificate
openssl pkcs12 -in <PFX_FILE> -nodes -nokeys -nomac -out domain.crt
# extracting the private key in encoded format
openssl pkcs12 -in <PFX_FILE> -nocerts -out domain.enc.key
# extracting the private key as PEM
openssl rsa -in domain.enc.key -outform PEM -out domain.key
```
