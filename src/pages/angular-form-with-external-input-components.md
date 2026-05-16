---
layout: ../layouts/GistLayout.astro
tags: [angular]
---

# Angular - form with external input components

If we wanted to use a form with external components (components from some library, for example), we still need to import Angular `FormsModule` and add it to the `imports` array even though we are not directly using anything from it. 

In absence of it, if the user submits an invalid form, the forms still gets submitted and page refresh happens. Importing `FormsModule` prevent that from happening.
