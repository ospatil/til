---
layout: ../layouts/GistLayout.astro
tags: [docker,linux]
---

# Docker - fixing permission denied error

The error can be fixed by:

1. adding the current user to the docker group: `sudo usermod -a -G docker $USER`
2. Logging out and logging back in.

[https://techoverflow.net/2017/03/01/solving-docker-permission-denied-while-trying-to-connect-to-the-docker-daemon-socket/](https://techoverflow.net/2017/03/01/solving-docker-permission-denied-while-trying-to-connect-to-the-docker-daemon-socket/)
