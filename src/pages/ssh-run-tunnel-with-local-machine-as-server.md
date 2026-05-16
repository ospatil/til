---
layout: ../layouts/GistLayout.astro
tags: [bash,ssh]
---

# ssh - run tunnel with local machine as server

It can be done using the following command: `ssh -fN -L <LOCAL_IP>:15432:<TARGET_IP_OR_HOST>:5432 <LOCAL_USER>@<LOCAL_IP>`

The above command forwards traffic on local IP : `15432` to `TARGET_IP_OR_HOST:5432`

Get local ip: `ifconfig en0`
