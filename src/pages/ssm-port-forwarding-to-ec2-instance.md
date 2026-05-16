---
layout: ../layouts/GistLayout.astro
tags: [aws]
---

# SSM port forwarding to EC2 instance

aws ssm start-session --target <INSTANCE_ID> --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '{"portNumber":["3389"],"localPortNumber":["3389"],"host":["<INSTANCE_PRIVATE_IP>"]}’
