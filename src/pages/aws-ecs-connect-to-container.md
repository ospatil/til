---
layout: ../layouts/GistLayout.astro
tags: [aws,cli]
---

# AWS ECS connect to container

```bash
aws ecs execute-command \
--cluster <CLUSTER_NAME> \
--task <TASK_ID> \
--container <CONTAINER_NAME> \
--interactive \
--command "/bin/bash"
```
