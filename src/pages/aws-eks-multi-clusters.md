---
layout: ../layouts/GistLayout.astro
tags: [aws,eks,kubernetes]
---

# AWS EKS multi-clusters

Some articles to go through as sort -

https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/use_cases/multi_cluster/

https://aws.amazon.com/blogs/containers/onfidos-journey-to-a-multi-cluster-amazon-eks-architecture/

https://aws.amazon.com/blogs/containers/how-to-leverage-application-load-balancers-advanced-request-routing-to-route-application-traffic-across-multiple-amazon-eks-clusters/

https://medium.com/@ajaypan2/multi-region-eks-cluster-for-active-failover-scenario-71d93fc6c4d7

[Ivo Pinto](https://pt.linkedin.com/in/ivopinto01/en?trk=public_post_feed-actor-name)

You think using a single K8s is complex? It is. But you can also deploy to multiple clusters. This is not for most people, but, AWS Load Balancer Controller v2.10+ introduced support for cross-cluster traffic. Before, load balancing traffic accross clusters using the same LBs was very difficult. Now, you have native support. A new parameter, multiClusterTargetGroup, allows the NLB to handle targets across multiple clusters. It's as simple as load balacing in a single cluster. Why would you ever do this? - You like complexity - Blue-green upgrades - Cluster upgrades and add-on updates - Workload resilience - Failover and disaster recovery If you are interested in the steps to configure it, they are detailed in the blog post: Building Resilient Multi-cluster Applications with Amazon EKS, Part 1: Implementing Cross-cluster Load Balancing with NLB.

![eks-alb-multi-cluster.jpeg](eks-alb-multi-cluster.jpeg)
