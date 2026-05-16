---
layout: ../layouts/GistLayout.astro
tags: [angular,frontend,typescript]
---

# Angular - typing DOM events

Event handlers in Angular components, receive event object but the type is generic and as a result, we can’t use the attributes of the DOM target element of the event. 

Here is how we can achieve it by using the TypeScript  `as` operator. 

```tsx
const target = event.target as HTMLInputElement;
// now we can use DOM attributes such as id, value etc. of the target
this.formModel[field] = target.value;
```
