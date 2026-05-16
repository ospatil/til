---
layout: ../layouts/GistLayout.astro
tags: [frontend, fundamentals]
---

# DOM Performance - Reflow and Repaint

## How the Browser Renders

1. Receives data (bytes) from the server
2. Parses and converts into tokens (`<`, TagName, Attribute, AttributeValue, `>`)
3. Turns tokens into nodes
4. Turns nodes into the DOM tree
5. Builds CSSOM tree from CSS rules
6. CSSOM and DOM trees combine into a RenderTree:
   - Computes which elements are visible and their computed styles
   - Not-visible elements (`meta`, `script`, `link`, `display: none`) are omitted
   - For each visible node, finds matching CSSOM rules and applies them
7. **Reflow**: compute the layout of each visible element (position and size)
8. **Repaint**: render the pixels to screen

## Repaint

Occurs when changes affect visibility but not layout.

Triggers: `opacity`, `color`, `background-color`, `visibility`

## Reflow (Layout / Layout Thrashing)

Occurs when changes affect the layout. More expensive than repaint.

Triggers: `width`, `position`, `float`, scrolling, user actions like `focus`

Key points:
- Changing a single element can affect all children, ancestors, siblings, or the whole document
- Reflow only has a cost if the document has changed and invalidated the layout
- **Something Invalidates + Something Triggers = Costly Reflow**

## Minimizing Repaints and Reflows

**Don't change styles with multiple statements:**
- Add a class instead
- Change `cssText` in one operation

**Batch DOM changes:**
- Use a `documentFragment` to hold temp changes
- Clone, update, replace the node
- Hide with `display: none` (1 reflow), make changes, restore display (total 2 reflows)

**Don't read computed styles repeatedly - cache them:**

The problem: read, write, read, write causes layout thrashing.

Bad - 6 costly reflows:

```js
var box1Height = document.getElementById('box1').clientHeight;
document.getElementById('box1').style.height = box1Height + 10 + 'px';

var box2Height = document.getElementById('box2').clientHeight;
document.getElementById('box2').style.height = box2Height + 10 + 'px';

// ... repeats for each box
```

Optimized - 1 reflow (batch reads, then batch writes):

```js
var box1Height = document.getElementById('box1').clientHeight;
var box2Height = document.getElementById('box2').clientHeight;
var box3Height = document.getElementById('box3').clientHeight;

document.getElementById('box1').style.height = box1Height + 10 + 'px';
document.getElementById('box2').style.height = box2Height + 10 + 'px';
document.getElementById('box3').style.height = box3Height + 10 + 'px';
```

## Performance Tips

- Avoid complex selectors - ID-based selectors are fastest
- Avoid jQuery selector extensions (`:even`, `:has`, `:gt`)
- Cache DOM references in variables
- Cache length during loops
- Add a `<style>` element for changing > 20 elements instead of `.css()` calls

## Resources

- [CSS Triggers](https://csstriggers.com/)
- [What forces layout/reflow](https://gist.github.com/paulirish/5d52fb081b3570c81e3a)
