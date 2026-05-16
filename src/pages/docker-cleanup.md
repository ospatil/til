---
layout: ../layouts/GistLayout.astro
tags: [docker]
---

# Docker - cleanup

To remove any stopped containers and all unused images (not just dangling images), use the `-a` flag to the command:

```bash
docker system prune -a
```
