---
layout: ../layouts/GistLayout.astro
tags: [database,docker,postgres]
---

# Postgres with docker and colima

Running Postgres using docker with data persistence

`docker run -d --rm -e POSTGRES_USER=postgresadmin -e POSTGRES_PASSWORD=postgresadmin -p 5432:5432 -v data:/var/lib/postgresql/data --name postgres postgres` 

Note the volume mapping where data is persisted in the `data` volume.

When running with `colima`  (or `finch`) directory mapping doesn’t work and volume mapping is the way.

Postgres client docker image

`docker run -it --rm jbergknoff/postgresql-client <DB_URL>`
