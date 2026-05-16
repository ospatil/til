---
layout: ../layouts/GistLayout.astro
tags: [frontend, fundamentals]
---

# DOM Performance - Reflow and Repaint

![Browser Rendering Pipeline](https://i.imgur.com/d8KxZSw.png)

## How the Browser Renders

- Receives the data (bytes) from the server
- Parses and converts into tokens (`<`, TagName, Attribute, AttributeValue, `>`)
- Turns tokens into nodes
- Turns nodes into the DOM tree
- Builds CSSOM tree from the CSS rules
- CSSOM and DOM trees are combined into a RenderTree:
  - Computes which elements are visible and their computed styles
  - Starting from the root of the DOM tree
  - Not-visible elements like (`meta`, `script`, `link`) and `display: none` are omitted from the render tree
  - For each visible node, find the appropriate matching CSSOM rules and apply them
- **Reflow**: compute the layout of each visible element (position and size)
- **Repaint**: render the pixels to screen

## Repaint

- Occurs when changes affect the visibility
- Trigger examples: `opacity`, `color`, `background-color`, `visibility`

## Reflow (Layout, LayoutFlush, LayoutThrashing)

- Occurs when the changes affect the layout
- Trigger examples: `width`, `position`, `float`
- Recalculates positions and dimensions
- Has a bigger impact - changing a single element can affect all children, ancestors, and siblings or the whole document
- Triggers: change DOM or CSS, scrolling, user actions like `focus`
- Reflow only has a cost if the document has changed and invalidated the layout
- **Something Invalidates + Something Triggers = Costly Reflow**

## Minimizing Repaints and Reflows

- Don't change styles by multiple statements, instead:
  - Add a `class`
  - Change the `cssText`
- Batch DOM changes:
  - Use a `documentFragment` to hold temp changes
  - Clone, update, replace the node
  - Hide the element with `display: none` (1 reflow, 1 repaint), add 100 changes, restore the display (total 2 reflow, 2 repaint)
- Don't ask for computed styles repeatedly, cache them into variable:
  - Multiple reads/writes (like for the `height` property of an element)
  - Writes, then reads, from the DOM, multiple times causing document reflows
  - Read (cached), write (invalidate layout), read (trigger layout)
  - **To fix: read everything first then write everything**

### Resources

- [CSS Triggers](https://csstriggers.com/)
- [What forces layout/reflow](https://gist.github.com/paulirish/5d52fb081b3570c81e3a)

## Chrome DevTools Performance

Chrome provides a great tool to figure out what's going on with your code - how many reflows (layout) and repaints, memory details, events, etc.

Bad code with 6 costly reflows (layout):

![Bad Code - 6 reflows](https://i.imgur.com/gn2fElE.png)

```js
var box1Height = document.getElementById('box1').clientHeight;
document.getElementById('box1').style.height = box1Height + 10 + 'px';

var box2Height = document.getElementById('box2').clientHeight;
document.getElementById('box2').style.height = box2Height + 10 + 'px';

var box3Height = document.getElementById('box3').clientHeight;
document.getElementById('box3').style.height = box3Height + 10 + 'px';

var box4Height = document.getElementById('box4').clientHeight;
document.getElementById('box4').style.height = box4Height + 10 + 'px';

var box5Height = document.getElementById('box5').clientHeight;
document.getElementById('box5').style.height = box5Height + 10 + 'px';

var box6Height = document.getElementById('box6').clientHeight;
document.getElementById('box6').style.height = box6Height + 10 + 'px';
```

Optimized to have 1 reflow:

![Optimized Code - 1 reflow](https://i.imgur.com/7x2IOiQ.png)

```js
var box1Height = document.getElementById('box1').clientHeight;
var box2Height = document.getElementById('box2').clientHeight;
var box3Height = document.getElementById('box3').clientHeight;
var box4Height = document.getElementById('box4').clientHeight;
var box5Height = document.getElementById('box5').clientHeight;
var box6Height = document.getElementById('box6').clientHeight;

document.getElementById('box1').style.height = box1Height + 10 + 'px';
document.getElementById('box2').style.height = box2Height + 10 + 'px';
document.getElementById('box3').style.height = box3Height + 10 + 'px';
document.getElementById('box4').style.height = box4Height + 10 + 'px';
document.getElementById('box5').style.height = box5Height + 10 + 'px';
document.getElementById('box6').style.height = box6Height + 10 + 'px';
```

## Performance Tips

- Optimize selectors:
  - Avoid jQuery selector extensions (`:even`, `:has`, `:gt`, `:eq`)
  - Avoid complex specificity
  - ID-based selectors are fastest
- Add a `<style>` element for changing > 20 elements instead of `.css()`
- Cache length during loops
- Avoid inspecting large numbers of nodes:
  - `document.getElementById('id').getElementsByTagName('*')` better than `document.getElementsByTagName('*')`
- Cache DOM values in script variables:
  - `var sample = document.getElementById('test')`
