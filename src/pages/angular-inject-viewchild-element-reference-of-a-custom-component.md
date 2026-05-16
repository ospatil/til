---
layout: ../layouts/GistLayout.astro
tags: [angular,frontend]
---

# Angular - Inject ViewChild element reference of a custom component

If we had a custom Angular component in our template and wanted to get reference to the underlying element reference so that we can read values directly from DOM, here is how it can be done:

1. The template will have the custom component with an element ref on it.

```html
<custom-input #myInput
```

1. The backing component class will look like this. The `read: ElementRef` will inject the underlying element reference.

```tsx
@ViewChild('myInput', { read: ElementRef, static: true })
myInput!: ElementRef<HTMLElement>;
```

1. The use the `myInput` reference anywhere in the component code as follows:

```tsx
this.myInput.nativeElement.querySelector('input')?.value
```

If we wanted to just inject the component, we can do it as follows. The `CustomInput` is the component class imported from the library that provides it. Here is a good article that provides the details (including how to inject a directive) - [https://blog.angular-university.io/angular-viewchild/](https://blog.angular-university.io/angular-viewchild/)

```tsx
@ViewChild('myInput', { static: true })
myInput!: CustomInput;
```

Related: 

[TypeScript definite assignment assertion operator](TypeScript%20definite%20assignment%20assertion%20operator%200c19c51cd3bd489da4c9c20c3c2e8483.md)
