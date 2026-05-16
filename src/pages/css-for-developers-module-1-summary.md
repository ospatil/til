---
layout: ../layouts/GistLayout.astro
tags: [css]
---

# CSS for developers - module 1 summary

- A good global reset

[My Global Styles • Treasure Trove](https://courses.joshwcomeau.com/css-for-js/treasure-trove/010-global-styles)

- A good intuition into css inheritance is it’s quite similar to JS prototypal inheritance.
    
    So, the `css` snippet on the left ca be thought of as `js` code on the right.
    

```jsx
<main style="color: black;">
  <p style="color: red;">
    Hello <span>World</span>
  </p>
</main>
```

CSS inheritance can be forced using `inherit`

```jsx
a {
  color: inherit;
}
```

```jsx

class Main {
  color = 'black'
}

class Paragraph extends Main {
  backgroundColor = 'red'
}

class Span extends Paragraph {
}

const s = new Span();

console.log(s.color)
```

- CSS cascade can be thought of as similar to JS merging.

```jsx
const appliedStyles = {
  ...inheritedStyles,
  ...tagStyles,
  ...classStyles,
  ...idStyles,
  ...inlineStyles,
  ...importantStyles
}
```

- Centring a child in a container can be done using `margin`

```jsx
.max-width-wrapper {
  margin: 0 auto;
  max-width: 800px; /* or width: <something like 50%> */
}
```

- The growing trend amongst developers is forgo margins altogether and use a combination of padding and layout components instead. A good article about it is

[Margin considered harmful](https://mxstbr.com/thoughts/margin/)

- `1 rem` is equal to `16px` by default. `rem` is a good measure for **font size**.
    
    `px` is still a good measure for borders. 
    
    For **bottom margin,** `rem` is a good unit since it scales and maintains the space between two elements even when the user cranks up the browser font size.
    
- For colours, `hsl` is the best unit. Here is a great article for CSS colour formats -

[Color Formats in CSS](https://www.joshwcomeau.com/css/color-formats/)

Here is another good explanation of how to use `hsl`: 

[Using HSL colors in CSS - LogRocket Blog](https://blog.logrocket.com/using-hsl-colors-css/)
