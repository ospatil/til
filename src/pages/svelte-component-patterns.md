---
layout: ../layouts/GistLayout.astro
tags: [svelte, ui, tailwind]
---

# Svelte 5 UI Component Libraries & Patterns

Strategies for building interactive, accessible UI components in Svelte 5 — covering DaisyUI, headless libraries (Melt UI, Bits UI), shadcn-svelte, CSS-only patterns, and how to combine them.

---

## Table of Contents

1. [The Problem: Styling vs Behavior](#1-the-problem-styling-vs-behavior)
2. [Library Landscape](#2-library-landscape)
3. [Decision Guide](#3-decision-guide)
4. [Patterns by Complexity](#4-patterns-by-complexity)
5. [Wrapping Components for Reuse](#5-wrapping-components-for-reuse)
6. [DaisyUI Theming](#6-daisyui-theming)
7. [CSS-Only Interactivity](#7-css-only-interactivity)
8. [Accessibility: When CSS-Only Isn't Enough](#8-accessibility-when-css-only-isnt-enough)
9. [DaisyUI + SvelteKit Setup](#9-daisyui--sveltekit-setup)

---

## 1. The Problem: Styling vs Behavior

UI components have two layers:

| Layer       | What it provides                                      | Examples                      |
| ----------- | ----------------------------------------------------- | ----------------------------- |
| **Styling** | Visual appearance, layout, colors, spacing            | DaisyUI, Tailwind, Bootstrap  |
| **Behavior**| Keyboard navigation, focus management, ARIA, state    | Melt UI, Bits UI, Radix       |

DaisyUI is CSS-only — it gives you beautiful Tailwind-based styling but no JavaScript behavior. When migrating from something like shadcn-svelte (which bundles both), you need a strategy for the behavior layer.

---

## 2. Library Landscape

### The Stack

```text
+-------------------------------------------+
|  shadcn-svelte                            |  <- Copied into your project
|  Pre-styled components (Tailwind)         |     Full design system, ready to use
+-------------------------------------------+
|  Bits UI                                  |  <- npm dependency
|  Unstyled Svelte components               |     Renders markup, exposes class/style props
+-------------------------------------------+
|  Melt UI                                  |  <- npm dependency
|  Headless builders (no markup)            |     Returns attributes, actions, stores
+-------------------------------------------+
```

### Comparison

|                        | Melt UI           | Bits UI            | shadcn-svelte          | DaisyUI (CSS-only) |
| ---------------------- | ----------------- | ------------------ | ---------------------- | ------------------- |
| **Abstraction**        | Builder functions | Svelte components  | Pre-styled components  | CSS classes         |
| **Renders markup**     | No                | Yes                | Yes                    | No (you write it)   |
| **Provides styling**   | No                | No                 | Yes (Tailwind)         | Yes (Tailwind)      |
| **Provides behavior**  | Yes               | Yes                | Yes                    | No                  |
| **Install method**     | npm package       | npm package        | Copied into src        | npm package         |
| **Upgrades**           | `npm update`      | `npm update`       | Re-run CLI / manual    | `npm update`        |
| **Structural control** | Total             | Moderate           | Limited (edit source)  | Total               |
| **Boilerplate**        | High              | Low                | Minimal                | Low                 |
| **Use with DaisyUI**   | Natural fit       | Works fine         | Conflicts (two systems)| N/A                 |
| **Bundle size impact** | Minimal (tree-shakes) | Small          | Depends on usage       | Zero JS             |

### When Each Makes Sense

- **Melt UI** — Maximum control over markup. Best when combining with a CSS library like DaisyUI because there's zero markup opinion to conflict with.
- **Bits UI** — Less boilerplate than Melt UI while still allowing you to pass your own classes (including DaisyUI classes).
- **shadcn-svelte** — Best when you want a complete design system out of the box. Don't combine with DaisyUI (two competing visual systems).
- **DaisyUI alone** — Sufficient for many components (buttons, cards, badges, alerts). Only add a headless library when you need complex interactive behavior.

---

## 3. Decision Guide

```text
Does the component need JS behavior?
         |
    +----+----+
    |         |
    NO        YES
    |         |
    v         v
DaisyUI    How complex is the behavior?
CSS-only         |
            +----+----+
            |         |
         Simple    Complex (focus trap, arrow keys,
            |      typeahead, ARIA live regions)
            v         |
     Svelte 5         v
     $state +     Need full DaisyUI markup control?
     onclick         |
                +----+----+
                |         |
               YES       NO (less boilerplate preferred)
                |         |
                v         v
            Melt UI    Bits UI
```

### Quick Lookup

| Component Type                        | Recommended Approach                    |
| ------------------------------------- | --------------------------------------- |
| Buttons, badges, cards, alerts        | DaisyUI CSS-only                        |
| Toggles, theme switches, swaps        | DaisyUI CSS-only (checkbox hack)        |
| Accordions (simple)                   | DaisyUI CSS-only (radio hack)           |
| Tabs, toasts, drawers                 | Svelte 5 `$state` + DaisyUI classes     |
| Dropdowns with keyboard nav           | Melt UI + DaisyUI classes               |
| Modals with focus trap                | Melt UI or Bits UI + DaisyUI classes    |
| Combobox / autocomplete               | Melt UI (complex ARIA)                  |
| Date picker                           | Melt UI or dedicated library            |
| Tooltips with positioning             | Bits UI (handles Floating UI internally)|
| Complete design system (no DaisyUI)   | shadcn-svelte                           |

---

## 4. Patterns by Complexity

### Tier 1: CSS-Only (DaisyUI Native)

No JavaScript needed. Instant interactivity on page load, zero hydration cost.

**Accordion:**

```svelte
<div class="join join-vertical w-full">
  <div class="collapse collapse-arrow join-item border border-base-300">
    <input type="radio" name="faq" checked />
    <div class="collapse-title font-medium">What is your refund policy?</div>
    <div class="collapse-content">
      <p>We offer a 30-day money-back guarantee.</p>
    </div>
  </div>
  <div class="collapse collapse-arrow join-item border border-base-300">
    <input type="radio" name="faq" />
    <div class="collapse-title font-medium">How do I cancel?</div>
    <div class="collapse-content">
      <p>Go to Settings → Subscription → Cancel.</p>
    </div>
  </div>
</div>
```

**Theme swap:**

```svelte
<label class="swap swap-rotate">
  <input type="checkbox" class="theme-controller" value="dark" />
  <svg class="swap-on h-6 w-6 fill-current"><!-- sun icon --></svg>
  <svg class="swap-off h-6 w-6 fill-current"><!-- moon icon --></svg>
</label>
```

### Tier 2: Svelte 5 Runes + DaisyUI

Simple state management with `$state`. Good for components where behavior is straightforward and custom a11y isn't critical.

**Tabs:**

```svelte
<script>
  let activeTab = $state('overview')
</script>

<div role="tablist" class="tabs tabs-bordered">
  {#each ['overview', 'settings', 'billing'] as tab}
    <button
      role="tab"
      class="tab"
      class:tab-active={activeTab === tab}
      aria-selected={activeTab === tab}
      onclick={() => activeTab = tab}
    >
      {tab[0].toUpperCase() + tab.slice(1)}
    </button>
  {/each}
</div>

<div class="p-4" role="tabpanel">
  {#if activeTab === 'overview'}
    <p>Overview content here.</p>
  {:else if activeTab === 'settings'}
    <p>Settings content here.</p>
  {:else}
    <p>Billing content here.</p>
  {/if}
</div>
```

**Toast notifications:**

```svelte
<script>
  let toasts = $state([])

  function addToast(message, type = 'info') {
    const id = crypto.randomUUID()
    toasts.push({ id, message, type })
    setTimeout(() => {
      toasts = toasts.filter(t => t.id !== id)
    }, 3000)
  }
</script>

<button class="btn btn-success" onclick={() => addToast('Item saved!', 'success')}>
  Save
</button>

<div class="toast toast-end">
  {#each toasts as toast (toast.id)}
    <div class="alert alert-{toast.type}">
      <span>{toast.message}</span>
    </div>
  {/each}
</div>
```

**Drawer:**

```svelte
<script>
  let drawerOpen = $state(false)
</script>

<div class="drawer">
  <input type="checkbox" class="drawer-toggle" bind:checked={drawerOpen} />
  <div class="drawer-content">
    <button class="btn btn-primary" onclick={() => drawerOpen = true}>
      Open Drawer
    </button>
  </div>
  <div class="drawer-side">
    <label class="drawer-overlay" onclick={() => drawerOpen = false}></label>
    <ul class="menu bg-base-200 text-base-content min-h-full w-80 p-4">
      <li><a href="/dashboard">Dashboard</a></li>
      <li><a href="/settings">Settings</a></li>
    </ul>
  </div>
</div>
```

### Tier 3: Bits UI + DaisyUI

Less boilerplate than Melt UI while still giving you class prop access. Good middle ground for components needing proper a11y.

**Dialog:**

```svelte
<script>
  import { Dialog } from 'bits-ui'
</script>

<Dialog.Root>
  <Dialog.Trigger class="btn btn-primary">Open Modal</Dialog.Trigger>
  <Dialog.Portal>
    <Dialog.Overlay class="modal-backdrop fixed inset-0 bg-black/50" />
    <Dialog.Content class="modal-box fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2">
      <Dialog.Title class="text-lg font-bold">Confirm Action</Dialog.Title>
      <Dialog.Description class="py-4">
        Are you sure you want to proceed?
      </Dialog.Description>
      <div class="modal-action">
        <Dialog.Close class="btn">Cancel</Dialog.Close>
        <button class="btn btn-primary" onclick={() => { /* confirm */ }}>
          Confirm
        </button>
      </div>
    </Dialog.Content>
  </Dialog.Portal>
</Dialog.Root>
```

**Tooltip:**

```svelte
<script>
  import { Tooltip } from 'bits-ui'
</script>

<Tooltip.Root>
  <Tooltip.Trigger class="btn btn-circle btn-ghost">?</Tooltip.Trigger>
  <Tooltip.Content class="tooltip tooltip-open tooltip-bottom" sideOffset={5}>
    <p>Helpful information here</p>
  </Tooltip.Content>
</Tooltip.Root>
```

### Tier 4: Melt UI + DaisyUI

Maximum control. You write all markup (using DaisyUI classes) and Melt UI provides the behavior via attributes and actions.

**Dropdown menu:**

```svelte
<script>
  import { createDropdownMenu } from '@melt-ui/svelte'
  const { trigger, menu, item, open } = createDropdownMenu()
</script>

<div class="dropdown" class:dropdown-open={$open}>
  <button class="btn" {...$trigger} use:trigger.action>
    Actions
  </button>

  {#if $open}
    <ul class="menu dropdown-content bg-base-200 rounded-box z-10 w-52 p-2 shadow"
        {...$menu} use:menu.action>
      <li><button class="btn btn-ghost btn-sm justify-start" {...$item} use:item.action>Edit</button></li>
      <li><button class="btn btn-ghost btn-sm justify-start" {...$item} use:item.action>Duplicate</button></li>
      <li><button class="btn btn-ghost btn-sm justify-start text-error" {...$item} use:item.action>Delete</button></li>
    </ul>
  {/if}
</div>
```

**Modal/Dialog:**

```svelte
<script>
  import { createDialog } from '@melt-ui/svelte'
  const { trigger, overlay, content, title, description, close, open } = createDialog()
</script>

<button class="btn btn-primary" {...$trigger} use:trigger.action>
  Open Modal
</button>

{#if $open}
  <div class="modal modal-open">
    <div class="modal-backdrop" {...$overlay} use:overlay.action></div>
    <div class="modal-box" {...$content} use:content.action>
      <h3 class="text-lg font-bold" {...$title} use:title.action>Confirm</h3>
      <p class="py-4" {...$description} use:description.action>
        Are you sure you want to proceed?
      </p>
      <div class="modal-action">
        <button class="btn" {...$close} use:close.action>Cancel</button>
        <button class="btn btn-primary" onclick={() => { /* handle confirm */ }}>
          Confirm
        </button>
      </div>
    </div>
  </div>
{/if}
```

---

## 5. Wrapping Components for Reuse

Encapsulate DaisyUI styling + behavior into reusable Svelte 5 components:

### Reusable Modal Component

```svelte
<!-- lib/components/Modal.svelte -->
<script>
  import { createDialog } from '@melt-ui/svelte'
  import type { Snippet } from 'svelte'

  let {
    triggerLabel = 'Open',
    triggerClass = 'btn btn-primary',
    title: titleText = '',
    children,
    actions: actionsSnippet
  }: {
    triggerLabel?: string
    triggerClass?: string
    title?: string
    children: Snippet
    actions?: Snippet
  } = $props()

  const { trigger, overlay, content, title, close, open } = createDialog()
</script>

<button class={triggerClass} {...$trigger} use:trigger.action>
  {triggerLabel}
</button>

{#if $open}
  <div class="modal modal-open">
    <div class="modal-backdrop" {...$overlay} use:overlay.action></div>
    <div class="modal-box" {...$content} use:content.action>
      {#if titleText}
        <h3 class="text-lg font-bold" {...$title} use:title.action>{titleText}</h3>
      {/if}
      <div class="py-4">
        {@render children()}
      </div>
      <div class="modal-action">
        <button class="btn" {...$close} use:close.action>Cancel</button>
        {#if actionsSnippet}
          {@render actionsSnippet()}
        {/if}
      </div>
    </div>
  </div>
{/if}
```

**Usage:**

```svelte
<script>
  import Modal from '$lib/components/Modal.svelte'
</script>

<Modal title="Delete Item" triggerLabel="Delete" triggerClass="btn btn-error">
  <p>This action cannot be undone.</p>

  {#snippet actions()}
    <button class="btn btn-error" onclick={handleDelete}>Delete Forever</button>
  {/snippet}
</Modal>
```

### Reusable Tabs Component

```svelte
<!-- lib/components/Tabs.svelte -->
<script>
  import type { Snippet } from 'svelte'

  let {
    tabs,
    active = $bindable(tabs[0]?.id ?? ''),
    variant = 'bordered',
    content
  }: {
    tabs: { id: string; label: string }[]
    active?: string
    variant?: 'bordered' | 'lifted' | 'boxed'
    content: Snippet<[string]>
  } = $props()
</script>

<div role="tablist" class="tabs tabs-{variant}">
  {#each tabs as tab}
    <button
      role="tab"
      class="tab"
      class:tab-active={active === tab.id}
      aria-selected={active === tab.id}
      onclick={() => active = tab.id}
    >
      {tab.label}
    </button>
  {/each}
</div>

<div role="tabpanel" class="p-4">
  {@render content(active)}
</div>
```

**Usage:**

```svelte
<script>
  import Tabs from '$lib/components/Tabs.svelte'

  const tabs = [
    { id: 'general', label: 'General' },
    { id: 'security', label: 'Security' },
    { id: 'notifications', label: 'Notifications' }
  ]
</script>

<Tabs {tabs}>
  {#snippet content(activeId)}
    {#if activeId === 'general'}
      <p>General settings...</p>
    {:else if activeId === 'security'}
      <p>Security settings...</p>
    {:else}
      <p>Notification preferences...</p>
    {/if}
  {/snippet}
</Tabs>
```

---

## 6. DaisyUI Theming

### Built-in Themes

DaisyUI includes 30+ themes. Activate them in your CSS:

```css
@import "tailwindcss";
@plugin "daisyui" {
  themes: light, dark, cupcake, dracula;
}
```

Apply a theme via `data-theme` on `<html>`:

```html
<html data-theme="dark">
```

### Theme Switching with Svelte 5

```svelte
<script>
  let theme = $state('light')

  $effect(() => {
    document.documentElement.setAttribute('data-theme', theme)
    localStorage.setItem('theme', theme)
  })

  // Restore on mount
  import { onMount } from 'svelte'
  onMount(() => {
    theme = localStorage.getItem('theme') ?? 'light'
  })
</script>

<select class="select select-bordered" bind:value={theme}>
  <option value="light">Light</option>
  <option value="dark">Dark</option>
  <option value="cupcake">Cupcake</option>
  <option value="dracula">Dracula</option>
</select>
```

### DaisyUI CSS Variables

Themes work through CSS custom properties. You can use them for custom components:

```css
/* These are set by the active theme */
background-color: oklch(var(--b1));       /* base-100 */
color: oklch(var(--bc));                   /* base-content */
border-color: oklch(var(--b3));            /* base-300 */
```

### Custom Theme

```css
@plugin "daisyui" {
  themes: light, dark --custom-theme {
    --color-base-100: oklch(0.98 0.01 240);
    --color-base-200: oklch(0.94 0.01 240);
    --color-base-300: oklch(0.90 0.01 240);
    --color-primary: oklch(0.60 0.20 260);
    --color-secondary: oklch(0.70 0.15 320);
    --border-radius-btn: 0.5rem;
  }
}
```

---

## 7. CSS-Only Interactivity

Modern CSS provides interactivity patterns without JavaScript. DaisyUI leverages these internally.

### Mechanisms

| Mechanism                  | Use Case                    | How It Works                          |
| -------------------------- | --------------------------- | ------------------------------------- |
| Checkbox/radio hack        | Toggles, accordions, swaps  | `:checked` state drives sibling CSS   |
| `<details>` / `<summary>` | Disclosure, simple dropdowns| Browser-native open/close             |
| `:focus-within`            | Dropdown visibility         | Parent matches when child is focused  |
| `<dialog>` element         | Modals                      | Native show/hide, backdrop, Escape    |
| `:has()` selector          | Parent-aware styling        | Style parent based on child state     |

### `:has()` Example (Parent-Aware Styling)

```css
/* Highlight card when its checkbox is checked */
.card:has(input:checked) {
  border-color: oklch(var(--p));
  box-shadow: 0 0 0 2px oklch(var(--p) / 0.2);
}
```

### CSS Transitions on Display Changes

New CSS capabilities allow animating elements that change `display`:

```css
.dropdown-content {
  display: none;
  opacity: 0;
  transition: opacity 0.2s, display 0.2s allow-discrete;
}

.dropdown:focus-within .dropdown-content {
  display: block;
  opacity: 1;
  @starting-style { opacity: 0; }
}
```

### Why It Matters for Svelte

- Zero hydration cost — interactive before JS loads
- Works with `prerender = true` and `csr = false` pages
- Reduces bundle size for simple interactions
- DaisyUI components that use these patterns work even without SvelteKit's client runtime

---

## 8. Accessibility: When CSS-Only Isn't Enough

CSS-only components lack behavior that keyboard and screen reader users need. Here's where the line is:

### CSS-Only Is Sufficient

| Component      | Why                                                    |
| -------------- | ------------------------------------------------------ |
| Accordion      | Radio/checkbox provides state; `<details>` is native   |
| Theme toggle   | Checkbox is natively keyboard-accessible               |
| Disclosure     | `<details>/<summary>` has built-in a11y                |
| Static alerts  | No interaction needed                                  |
| Cards, badges  | Purely visual                                          |

### JavaScript Required

| Component      | What's missing without JS                              |
| -------------- | ------------------------------------------------------ |
| Dropdown menu  | Arrow key navigation, typeahead, focus management      |
| Modal/dialog   | Focus trap, return focus on close, Escape handling     |
| Combobox       | Filtering, ARIA `aria-activedescendant`, announcements |
| Tabs           | Arrow key switching, `aria-selected` management        |
| Tooltip        | Positioning (Floating UI), delay, escape dismissal     |
| Date picker    | Grid navigation, range selection, announcements        |
| Toast          | `aria-live` region, auto-dismiss timing                |

### The Practical Rule

If the component involves **focus management**, **arrow key navigation**, or **dynamic ARIA attributes**, you need JavaScript. Use Melt UI or Bits UI for these — don't hand-roll the behavior.

For the Svelte 5 runes patterns (Tier 2 above), you get basic interactivity but should add ARIA attributes manually:

```svelte
<!-- Tabs: add aria attributes yourself -->
<button
  role="tab"
  aria-selected={active === tab.id}
  aria-controls="panel-{tab.id}"
  tabindex={active === tab.id ? 0 : -1}
>
```

For Melt UI / Bits UI (Tier 3-4), ARIA attributes are handled automatically.

---

## 9. DaisyUI + SvelteKit Setup

```bash
npx sv create ./
npm install tailwindcss@latest @tailwindcss/vite@latest daisyui@latest
```

`vite.config.js`:
```javascript
import tailwindcss from "@tailwindcss/vite"
import { sveltekit } from "@sveltejs/kit/vite"
import { defineConfig } from "vite"

export default defineConfig({
  plugins: [tailwindcss(), sveltekit()],
})
```

`src/app.css`:
```css
@import "tailwindcss";
@plugin "daisyui";
```

### Optional: Add Melt UI

```bash
npm install @melt-ui/svelte @melt-ui/pp
```

`svelte.config.js` (preprocessor for shorthand syntax):
```javascript
import { preprocessMeltUI } from '@melt-ui/pp'
import sequence from 'svelte-sequential-preprocessor'

export default {
  preprocess: sequence([/* other preprocessors */, preprocessMeltUI()])
}
```

### Optional: Add Bits UI

```bash
npm install bits-ui
```

No additional config needed — Bits UI is a standard Svelte component library.

---

## References

- [DaisyUI SvelteKit docs](https://daisyui.com/docs/install/sveltekit/)
- [DaisyUI Themes](https://daisyui.com/docs/themes/)
- [Melt UI](https://melt-ui.com)
- [Bits UI](https://bits-ui.com)
- [shadcn-svelte](https://shadcn-svelte.com)
