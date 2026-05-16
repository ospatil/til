---
layout: ../layouts/GistLayout.astro
tags: [angular]
---

# Angular material custom themes

Here is a complete **Angular Material 16** custom theme.

It’s a good idea to define css variables for colours and typography, load them before the theme  to make the theme reusable.

```scss
// Custom Theming for Angular Material
// For more information: https://material.angular.io/guide/theming
// @use 'sass:map';
@use '@angular/material' as mat;
// Plus imports for other components in your app.

// Include the common styles for Angular Material. We include this here so that you only
// have to load a single css file for Angular Material in your app.
// Be sure that you only ever include this mixin once!
@include mat.core();

$custom-primary-map: (
  50: #E6F1FF,
  100: #C9DBED,
  200: #AEC3D8,
  300: #91A9C3,
  400: #7B96B2,
  500: #6483A2,
  600: #567490,
  700: #466079,
  800: #374D62,
  900: #25384A,
  contrast: (
    50: var(text-primary),
    100: var(text-primary),
    200: var(text-primary),
    300: var(text-light),
    400: var(text-light),
    500: var(text-light),
    600: var(text-light),
    700: var(text-light),
    800: var(text-light),
    900: var(text-light)
  )
);

$custom-accent-map: (
  50: #E6EFFF,
  100: #c6D8EC,
  200: #AABDD5,
  300: #8CA2BE,
  400: #758DAC,
  500: #5E7A9B,
  600: #506B89,
  700: #405872,
  800: #31455C,
  900: #1F3144,
  contrast: (
    50: var(text-primary),
    100: var(text-primary),
    200: var(text-primary),
    300: var(text-light),
    400: var(text-light),
    500: var(text-light),
    600: var(text-light),
    700: var(text-light),
    800: var(text-light),
    900: var(text-light)
  )
);

$custom-warn-map: (
  50: #F7E8EA,
  100: var(color-red-100),
  200: #D1908E,
  300: #BC6865,
  400: #BF4B43,
  500: var(color-red-500),
  600: #B0352A,
  700: var(color-red-700),
  800: #92281F,
  900: var(color-red-900),
  contrast: (
    50: var(text-primary),
    100: var(text-primary),
    200: var(text-primary),
    300: var(text-light),
    400: var(text-light),
    500: var(text-light),
    600: var(text-light),
    700: var(text-light),
    800: var(text-light),
    900: var(text-light),
  )
);

// Define the palettes for your theme using the Material Design palettes available in palette.scss
// (imported above). For each palette, you can optionally specify a default, lighter, and darker
// hue. Available color palettes: https://material.io/design/color/
$custom-primary: mat.define-palette($custom-primary-map, 500, 100, 900);
$custom-accent: mat.define-palette($custom-accent-map, 500, 100, 900);

$custom-warn: mat.define-palette($custom-warn-map, 500, 100, 900);

$custom-typography: mat.define-typography-config(
  $headline-1: mat.define-typography-level(
    $font-family: var(font-families-heading),
    $font-weight: var(font-weights-bold),
    $font-size: var(font-sizes-h1),
    $line-height: var(line-heights-h1)
  ),
  $headline-2: mat.define-typography-level(
    $font-family: var(font-families-heading),
    $font-weight: var(font-weights-bold),
    $font-size: var(font-sizes-h2),
    $line-height: var(line-heights-h2)
  ),
  $headline-3: mat.define-typography-level(
    $font-family: var(font-families-heading),
    $font-weight: var(font-weights-bold),
    $font-size: var(font-sizes-h3),
    $line-height: var(line-heights-h3)
  ),
  $headline-4: mat.define-typography-level(
    $font-family: var(font-families-heading),
    $font-weight: var(font-weights-bold),
    $font-size: var(font-sizes-h4),
    $line-height: var(line-heights-h4)
  ),
  $headline-5: mat.define-typography-level(
    $font-family: var(font-families-heading),
    $font-weight: var(font-weights-bold),
    $font-size: var(font-sizes-h5),
    $line-height: var(line-heights-h5)
  ),
  $headline-6: mat.define-typography-level(
    $font-family: var(font-families-heading),
    $font-weight: var(font-weights-bold),
    $font-size: var(font-sizes-h6),
    $line-height: var(line-heights-h6)
  ),
  $subtitle-1: mat.define-typography-level(
    $font-family: var(font-families-heading),
    $font-weight: var(font-weights-semibold),
    $font-size: var(font-sizes-h3),
    $line-height: var(line-heights-h3)
  ),
  $subtitle-2: mat.define-typography-level(
    $font-family: var(font-families-heading),
    $font-weight: var(font-weights-medium),
    $font-size: var(font-sizes-h4),
    $line-height: var(line-heights-h4)
  ),
  $body-1: mat.define-typography-level(
    $font-family: var(font-families-body),
    $font-weight: var(font-weights-regular),
    $font-size: var(font-sizes-text),
    $line-height: var(line-heights-text)
  ),
  $body-2: mat.define-typography-level(
    $font-family: var(font-families-body),
    $font-weight: var(font-weights-regular),
    $font-size: var(font-sizes-text),
    $line-height: var(line-heights-text)
  ),
  $caption: mat.define-typography-level(
    $font-family: var(font-families-body),
    $font-weight: var(font-weights-regular),
    $font-size: var(font-sizes-caption),
    $line-height: var(line-heights-caption)
  ),
);

// Create the theme object. A theme consists of configurations for individual
// theming systems such as "color" or "typography".
$custom-theme: mat.define-light-theme((
  color: (
    primary: $custom-primary,
    accent: $custom-accent,
    warn: $custom-warn,
  ),
  typography: $custom-typography
));

// Include theme styles for core and each component used in your app.
// Alternatively, you can import and @include the theme mixins for each component
// that you are using.
@include mat.all-component-themes($custom-theme);

/* You can add global styles to this file, and also import other style files */

html, body { height: 100%; }
body { margin: 0; font-family: var(font-families-body); }
```

This theme can be exported from an Angular library as shown below (snippet from `package.json`):

```scss
"exports": {
    "./themes/custom-material-theme.scss": {
      "sass": "./themes/custom-material-theme.scss"
    },
    "./themes/custom-tailwind-preset.cjs": {
      "default": "./themes/custom-tailwind-preset.cjs"
    }
  },
```

The applications can then import it in its `theme.scss` file as follows:

```scss
// import custom theme
@use "@myorg/my-lib/themes/custom-material-theme.scss" as theme;
@use 'sass:map';

// You can use the individual elements of the theme as follows. 
$color-primary-100: map-get(theme.$custom-primary-map, 100);
// Then import this file in individual component scss files and use the variable as
// @use '../<RELATIVE_PATH>/theme.scss' as theme;

// .mat-mdc-header-row {
//   background-color: theme.$color-primary-100;
//}
```
