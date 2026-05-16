---
layout: ../layouts/GistLayout.astro
tags: [docker]
---

# Docker - healthchecks

Example healthchek in `docker-compose.yml` for a http service running on port `3000`.

```yaml
api:
...
...    
	healthcheck:
		test: nc -zv localhost 3000 || exit 1
		interval: 60s
		retries: 5
		start_period: 20s
		timeout: 10s
```

The dependent services can then wait for `service-healthy` condition.

```yaml
depends_on:    
	api:
	condition: service_healthy
```
