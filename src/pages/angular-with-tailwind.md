---
layout: ../layouts/GistLayout.astro
tags: [angular,frontend,tailwind]
---

# Angular with tailwind

There are many possible scenarios for using Tailwindcss with Angular. This NX blog entry sums it well - [https://blog.nrwl.io/set-up-tailwind-css-with-angular-in-an-nx-workspace-6f039a0f4479](https://blog.nrwl.io/set-up-tailwind-css-with-angular-in-an-nx-workspace-6f039a0f4479)

One of the scenarios is - using Tailwindcss in an Angular library without precompiling the CSS with the knowledge that the actual Angular application that’s going to use the library will have right Tailwindcss configuration in place. We can create a *preset* in the library and publish the Angular library in usual fashion.

Here is how the application `tailwind.config.cjs` looks like:

```tsx
const { createGlobPatternsForDependencies } = require('@nx/angular/tailwind');
const { join } = require('path');
const sharedTailwindConfig = require('@myorg/my-lib/themes/gcds-tailwind-preset.cjs');

/** @type {import('tailwindcss').Config} */
module.exports = {
	// import preset from the library
  presets: [sharedTailwindConfig],
  content: [
    // @myorg/my-lib Angular lib uses tailwindcss in partials. The following line will allow tailwindcss to process it from within node_modules.
    './node_modules/@myorg/my-lib/esm2022/**/*.mjs',
    join(__dirname, 'src/**/!(*.stories|*.spec).{ts,html}'),
    ...createGlobPatternsForDependencies(__dirname),
  ],
};
```

More here: [https://stackoverflow.com/questions/71695814/tailwind-not-being-applied-to-library/72208906#72208906](https://stackoverflow.com/questions/71695814/tailwind-not-being-applied-to-library/72208906#72208906)
