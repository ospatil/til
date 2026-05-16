---
layout: ../layouts/GistLayout.astro
tags: [kubernetes]
---

# Kubernetes - running a pod for debugging

Kubernetes Running a pod for debugging

```bash
kubectl run curl-debug --rm -i --tty --restart=Never --image=radial/busyboxplus:curl -- /bin/sh
```

- The `-restart=Never` flag is what it says to create a *Pod* instead of a *Deployment* object.
- `radial/busyboxplus:curl` is a lightweight image for network debugging.
