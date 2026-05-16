---
layout: ../layouts/GistLayout.astro
tags: [bash,docker,npm]
---

# Docker image tag using bash date

```bash
export TAG=`date +'%s'` && echo 'New Tag:' && printenv TAG && docker build --platform linux/amd64 -t <IMAGE_NAME>:${TAG} .`
```

`date +'%s'` gives the current timestamp in bash.
