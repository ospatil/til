---
layout: ../layouts/GistLayout.astro
tags: [jwt]
---

# Decode jwt tokens using jq

`jq -R 'split(".") | select(length > 0) | .[0],.[1] | @base64d | fromjson' <<< [TOKEN]`
