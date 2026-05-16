---
layout: ../layouts/GistLayout.astro
tags: [aws,cli]
---

# AWS connect to db in private subnet using PgAdmin UI

1. Get the token to be used as password in pgadmin ui

```bash
aws rds generate-db-auth-token \
	--hostname <RDS_PROXY_ENDPOINT> \
	--port 5432 \
	--region <AWS-REGION \
	--username <DB_USER>>
```

1. Start SSM forwarding session

```bash
aws ssm start-session \
	--region <AWS_REGION> \
	--target <BASTION_EC2_INSTANCE_ID> \
	--document-name AWS-StartPortForwardingSessionToRemoteHost \
	--parameters host="<RDS_PROXY_ENDPOINT>",portNumber="5432",localPortNumber="5432"
```

1. Connect using PgAdmin with `127.0.0.1` as host and username and token as password.
