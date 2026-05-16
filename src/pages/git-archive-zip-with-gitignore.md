---
layout: ../layouts/GistLayout.astro
tags: [git]
---

# Git - Generate Zip Archive Respecting .gitignore

Create a zip archive of a git repository that excludes `.git/` and respects `.gitignore`:

```bash
git archive -o archive.zip HEAD
```

## Excluding Additional Files

Use `.gitattributes` to exclude files from `git archive`:

1. Create `.gitattributes` in your project root
2. Add exclusion patterns with `export-ignore`:

```
.gitattributes export-ignore
.gitignore export-ignore
/mytemp export-ignore
```

3. Commit the `.gitattributes` file (otherwise `git archive` won't pick up the settings)

## Use Case

When you want to distribute a source + binaries snapshot that includes:
- All source files
- Built binaries and dist folder
- But not `.git/`, hidden files like `.cache`, or `node_modules/`

The trick is that `git archive` only includes tracked files. For including untracked build outputs, combine with a separate zip step or use a build script that archives after build.
