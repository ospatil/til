---
layout: ../layouts/GistLayout.astro
tags: [docker]
---

# Docker - loki integration

Add `loki` log aggregation using the following config

```yaml
api:
...
...
	logging:
		driver: loki
		options:
			loki-url: "http://<HOST>:3100/loki/api/v1/push"
```
