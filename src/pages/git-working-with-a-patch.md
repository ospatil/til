---
layout: ../layouts/GistLayout.astro
tags: [git]
---

# Git - working with a patch

- Create a patch from existing commit: `git show <COMMIT_HASH> > patch1.patch`
- Creating patch for recent commits by resetting
    
    ```bash
    git reset --soft HEAD~1git diff --cached > patch1.patch
    ```
    
- Apply patch: `git apply patch1.patch`
