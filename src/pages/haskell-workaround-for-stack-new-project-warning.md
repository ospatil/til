---
layout: ../layouts/GistLayout.astro
tags: [haskell]
---

# Haskell - workaround for stack new project warning

A warning shows up while running `stack ghci` in a new project:

```bash
Warning: Multiple files use the same module name:         * Paths_myproj found at the following paths           * /home/user/temp/myproj/.stack-work/dist/x86_64-linux/Cabal-3.0.1.0/build/autogen/Paths_myproj.hs (myproj:lib)           * /home/user/temp/myproj/.stack-work/dist/x86_64-linux/Cabal-3.0.1.0/build/myproj-exe/autogen/Paths_myproj.hs (myproj:exe:myproj-exe)
```

Workaround:

Add the following to the end of `executables` and `tests` sections in `package.yaml`.

```yaml
when:
- condition: false
	other-modules: Paths_pkg
```

where `pkg` is our package name.

[https://github.com/commercialhaskell/stack/issues/5439#issuecomment-735850892](https://github.com/commercialhaskell/stack/issues/5439#issuecomment-735850892)
