---
layout: ../layouts/GistLayout.astro
tags: [mac,tools]
---

# Get memory of the process of macOS process

Use the Apple-supplied`/usr/bin/time -l <DO SOMETHING>`

It is important to use the full path `/usr/bin/time` because `time` calls bash and results in error: `-bash: -l: command not found`

[https://stackoverflow.com/a/41207962](https://stackoverflow.com/a/41207962)
