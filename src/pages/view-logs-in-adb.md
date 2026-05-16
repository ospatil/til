---
layout: ../layouts/GistLayout.astro
tags: [android,cli]
---

# View logs in ADB

For example, see `tak` logs - 

```bash
adb logcat | grep -F `adb shell ps | grep com.atakmap.app | tr -s '[:space:]' ' ' | cut -d ' ' -f2`
```
