---
layout: ../layouts/GistLayout.astro
tags: [database,docker,nodejs]
---

# Prisma - run prisma migrate in docker

Create a separate docker file - `Dockerfile-prisma-migrate` -

```docker
FROM node:18-alpine AS build
WORKDIR /usr/src/app
COPY ./prisma/ prisma/
COPY package.prismamigrate.json package.json
RUN npm i
RUN npm run prisma -- generate
CMD [  "npm", "run", "prisma:migrate"]
```

The `package.prismamigrate.json` looks like this -

```json
    
"dependencies": {
    "@prisma/client": "^4.11.0"
  },
  "devDependencies": {
    "prisma": "^4.11.0",
    "ts-node": "^10.9.1",
    "typescript": "^4.9.5"
  },
  "prisma": {
    "seed": "ts-node prisma/seed/seed.ts"
  }
```

Then in the main `pakcage.json` file, create the image as follows -

```json
"docker:build:prisma-migrate": "docker build --platform linux/amd64 -t my-prisma-migrate --file Dockerfile-prisma-migrate ."
```
