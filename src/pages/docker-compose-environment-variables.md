---
layout: ../layouts/GistLayout.astro
tags: [docker]
---

# Docker compose - environment variables

Pass environment variables without hard-coding them in the the `docker-compose.yml` file.

```yaml
environment:  
	- DATABASE_URL=${DB_URL}
```

Then set the value for `DB_URL` in the `.env` file in the same directory as `docker-compose.yml` file.
