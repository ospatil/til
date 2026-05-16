---
layout: ../layouts/GistLayout.astro
tags: [aws,data]
---

# AWS VPC flow logs + OpenSearch

There are multiple ways to send VPC flow logs to OpenSearch Cluster

1. Publish to CloudWatch logs → Subscription Filter → OpenSearch (uses AWS-managed Lambda internally)
    
    [https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-cwl.html](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-cwl.html)
    
    [https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_OpenSearch_Stream.html](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_OpenSearch_Stream.html)
    
2. Publish directly to Amazon Data Firehose → OpenSearch
    
    [https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-firehose.html](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-firehose.html)
    
3. Publish to S3 → OpenSearch
    
    [https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-s3.html](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-s3.html)
    
    [https://docs.aws.amazon.com/opensearch-service/latest/developerguide/integrations-s3-lambda.html](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/integrations-s3-lambda.html)
