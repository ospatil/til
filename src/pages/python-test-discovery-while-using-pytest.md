---
layout: ../layouts/GistLayout.astro
tags: [python]
---

# Python - test discovery while using pytest

Name the test files or directories with either `test_` prefix or `_test` suffix. Dash doesn’t work since it’s not a valid python module name. More details here: [https://stackoverflow.com/questions/3295386/python-unittest-and-discovery/6672873#6672873](https://stackoverflow.com/questions/3295386/python-unittest-and-discovery/6672873#6672873)

Also, in VS Code somehow the `unittest` discovery for tests in sub-directories doesn’t work, but `pytest` does.
