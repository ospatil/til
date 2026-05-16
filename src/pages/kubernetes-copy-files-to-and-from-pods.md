---
layout: ../layouts/GistLayout.astro
tags: [kubernetes]
---

# Kubernetes - copy files to and from pods

Kubernetes - copy files to and from pods

General format: `kubectl cp <src> <dest>`.

- Copy from local to pod: `kubectl cp /path/to/file my-pod:/path/to/file`.
- Copy from pod to pod: `kubectl cp pod-1:my-file pod-2:my-file`.
- Copy from pod to local: `kubectl cp my-pod:my-file my-file`.
- Copy directories: `kubectl cp my-dir my-pod:my-dir`.
- Specifying a container when there are multiple containers in a pod: `kubectl cp my-file my-pod:my-file -c my-container-name`.
