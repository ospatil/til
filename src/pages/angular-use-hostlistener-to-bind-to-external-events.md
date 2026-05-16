---
layout: ../layouts/GistLayout.astro
tags: [angular,frontend]
---

# Angular - use HostListener to bind to external events

Suppose we have a custom component, say something like `stenciljs` web component exported as angular component and we would like to listen to some event exposed by that component (using something like `@Event() compCustemEvent: EventEmitter;` in the `stenciljs` code). 

It can be done using `@HostListener` in an angular component as follows:

```tsx
@HostListener('compCustemEvent', ['$event'])
  emailValidEvent(event: CustomEvent) {
    console.log('compCustemEvent', event);
  }
```
