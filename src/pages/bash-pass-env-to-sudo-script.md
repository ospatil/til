---
layout: ../layouts/GistLayout.astro
tags: [bash]
---

# Bash pass env to sudo script

To pass the current environment to a script that is being run as `sudo`, use the `-E` flag.

`sudo -E ./myscript.sh`
