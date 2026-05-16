---
layout: ../layouts/GistLayout.astro
tags: [coredns,dns]
---

# Coredns - hosts and forward config

Here is how the `Corefile` looks like when using `hosts` plugin to resolve some hosts and then forwarding to the local system handling through `/etc/resolv.conf`.

```
.:53 {
   log
   errors
   hosts {
     192.168.0.25 host1.local
     192.168.0.26 host2.local
        fallthrough
   }
   forward . /etc/resolv.conf
}
```
