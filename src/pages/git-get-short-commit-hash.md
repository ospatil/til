---
layout: ../layouts/GistLayout.astro
tags: [git]
---

# Git - get short commit hash

- Get short versions of `git log` and `git show`
    
    ```bash
    git log --onelinegit show --oneline
    ```
    
- Get short hash of head: `git rev-parse --short HEAD`
- Abbreviate long hash to short(7 digits default) : `git rev-parse --short <LONG_HASH>`
- Abbreviate long hash to shortest (4 digits) : `git rev-parse --short=4 <LONG_HASH>`
