---
layout: ../layouts/GistLayout.astro
tags: [aws]
---

# AWS application considerations - load balancers, API Gateway, CloudFront, Lambda

Some notes on when to use what when it comes to ALB and NLB.

1. If we want unbroken end-to-end connection between client and target, only NLB can be used. 
2. To use a TLS listener, you must deploy at least one server certificate on your load balancer. The load balancer uses a server certificate to terminate the front-end connection and then to decrypt requests from clients before sending them to the targets.
3. Network Load Balancers do not support TLS renegotiation or mutual TLS authentication (mTLS). For mTLS support, create a TCP listener instead of a TLS listener. The load balancer passes the request through as is, so you can implement mTLS on the target. The mTLS has to be handled by the target in this case.
    
    Reference for 2 and 3 - https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html
    
4. If you must ensure that the targets decrypt HTTPS traffic instead of the load balancer, you can create a Network Load Balancer with a TCP listener on port 443. With a TCP listener, the load balancer passes encrypted traffic through to the targets without decrypting it.
    
    Reference - https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html#listener-configuration
    
5. ALB can make use of self-signed certificates. For example, the ALB can terminate client TLS connection that uses domain certificate and re-encrypt connection to target using a self-signed certificate. Good article on it - https://aws.amazon.com/blogs/containers/maintaining-transport-layer-security-all-the-way-to-your-container-using-the-application-load-balancer-with-amazon-ecs-and-envoy/
6. Good article that shows how to implement mTLS using ALB - https://aws.amazon.com/blogs/aws/mutual-authentication-for-application-load-balancer-to-reliably-verify-certificate-based-client-identities/

API Gateway integration

- Private integrations enable you to create API integrations with private resources in a VPC, such as Application Load Balancers or Amazon ECS container-based applications.
- To create a private integration, you must first create a VPC link.
- After you’ve created a VPC link, you can set up private integrations that connect to an **Application Load Balancer**, **Network Load Balancer**, or resources registered with an AWS **Cloud Map service**.

Reference - https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-private.html

Good article on implementation - https://aws.amazon.com/blogs/architecture/field-notes-integrating-http-apis-with-aws-cloud-map-and-amazon-ecs-services/

Limiting access to S3 static website only through CloudFront - https://stackoverflow.com/a/77657751

### Using API Gateway with ECS

When using ECS, we have the option to expose your services with API Gateway and [AWS Cloud Map](https://aws.amazon.com/cloud-map/) instead of a load balancer.

Reference article - https://aws.amazon.com/blogs/architecture/field-notes-serverless-container-based-apis-with-amazon-ecs-and-amazon-api-gateway/

### Custom domain with APIG

Use api mappings to connect API stages to a custom domain name

https://docs.aws.amazon.com/apigateway/latest/developerguide/rest-api-mappings.html

Lambda URL and CloudFront with OAC

- For simpler  applications and SSR applications, Lambda function URL can be created and configured as origin in CloudFront and secured using OAC - https://aws.amazon.com/blogs/networking-and-content-delivery/secure-your-lambda-function-urls-using-amazon-cloudfront-origin-access-control/
- The frontend static part can be deployed on S3, configured as origin in CloudFront and protected by OAC.
- The SSR backend can be deployed as Lambda, exposed as function URL, configured as origin in CloudFront and protected by OAC as mentioned in article above.
- The frontend can use Amplify auth to authentication with Cognito.
- Lambda@edge can be configured for verifying tokens before request is sent to backend - https://aws.amazon.com/blogs/networking-and-content-delivery/authorizationedge-how-to-use-lambdaedge-and-json-web-tokens-to-enhance-web-application-security/
- Provisioned concurrency can be used  to keep a number of pre-initialized execution environments allocated to the lambda function. These execution environments are ready to respond immediately to incoming function requests. This acts as sort-of always running server-side component.
- The function URL works even when the lambda is bound to VPC. You may have to bind the lambda to VPC if it wants to access a RDS database. Such function URL will work if it is behind a load balancer, API Gateway or Cloudfront.

On separate note, here is how to allow Lambda to connect to database in VPC - https://repost.aws/knowledge-center/connect-lambda-to-an-rds-instance

Deploying webapps as Lambda functions without needing to adapt the code

[Lambda Web Adapter](https://github.com/awslabs/aws-lambda-web-adapter) (LWA) is an open-source project that enables running Web apps on Lambda functions without the need to change or adapt the code.

[https://dev.to/aws-builders/adding-flexibility-to-your-deployments-with-lambda-web-adapter-42m2](https://dev.to/aws-builders/adding-flexibility-to-your-deployments-with-lambda-web-adapter-42m2)
