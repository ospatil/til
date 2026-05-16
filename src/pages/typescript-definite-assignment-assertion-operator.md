---
layout: ../layouts/GistLayout.astro
tags: [angular,frontend,typescript]
---

# TypeScript definite assignment assertion operator

Consider the code snippet: ``someField!: ElementRef<HTMLElement>``

The **`!`** operator is known as the "definite assignment assertion" operator, which tells TypeScript that the property will be assigned a value, even if it's initially declared as uninitialized or **`null`**.
