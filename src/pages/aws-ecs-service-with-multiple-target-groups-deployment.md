---
layout: ../layouts/GistLayout.astro
tags: [aws,docker]
---

# AWS: ecs service with multiple target groups deployment

If an ECS service has multiple target groups associated with it

> • The service must use the rolling update (`ECS`) deployment controller type.
> 

[https://docs.aws.amazon.com/AmazonECS/latest/developerguide/register-multiple-targetgroups.html#multiple-targetgroups-considerations](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/register-multiple-targetgroups.html#multiple-targetgroups-considerations)
