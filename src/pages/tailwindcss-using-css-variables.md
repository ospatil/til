---
layout: ../layouts/GistLayout.astro
tags: [frontend,tailwind]
---

# Tailwindcss - using css variables

Here is how we can use css variables in various ways with tailwindcss:

[https://play.tailwindcss.com/aot2ECvFXC](https://play.tailwindcss.com/aot2ECvFXC)

The `[length:--text-size]` syntax in `text-[length:--text-size]`and `text-[color:--text-color]` is way of avoiding ambiguities using CSS data type `length:` before the value.

More details here - [https://tailwindcss.com/docs/adding-custom-styles#resolving-ambiguities](https://tailwindcss.com/docs/adding-custom-styles#resolving-ambiguities)

The tailwindcss documentation states that:

> When using a CSS variable as an arbitrary value, wrapping your variable in **`var(...)`** isn’t needed — just providing the actual variable name is enough. Ref - [https://tailwindcss.com/docs/adding-custom-styles#using-arbitrary-values](https://tailwindcss.com/docs/adding-custom-styles#using-arbitrary-values)
>
