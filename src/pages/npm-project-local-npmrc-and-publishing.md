---
layout: ../layouts/GistLayout.astro
tags: [aws,nodejs,npm]
---

# npm - project local .npmrc and publishing

Having a local `.npmrc` in a project folder is a great way to ensure that different projects remain independent and you can use different configurations for each. 

It can be achieved by auto-generating the `.npmrc` file. 

Consider the scenario - we are using AWS CodeArtifact to publish custom packages. We can login into it and add the registry coordinates in the `.npmrc` as shown below:

```bash
REGION=us-east-1
DOMAIN_NAME=mydomain
REPO_NAME=myrepo
DOMAIN_OWNER=<ACCOUNT_ID>
REGISTRY="$DOMAIN_NAME-$DOMAIN_OWNER.d.codeartifact.$REGION.amazonaws.com/npm/$REPO_NAME/
```

Here is the login script that sets up `.npmrc` at the root of the project folder. Note that we are setting custom registry only for our org (`npm config set @myorg:registry` below) while using the default NPM registry for open-source packages.

```bash
#!/bin/bash -e
source .env
touch .npmrc
CODEARTIFACT_AUTH_TOKEN=`aws codeartifact get-authorization-token --domain $DOMAIN_NAME --domain-owner $DOMAIN_OWNER --region $REGION --query authorizationToken --output text`
npm config set @myorg:registry="https://$REGISTRY" --userconfig .npmrc
npm config set //$REGISTRY:_authToken=$CODEARTIFACT_AUTH_TOKEN --userconfig .npmrc
echo "Logged into CodeArtifact successfully"
```

The packages in the project can be published using a script below:

```bash
#!/bin/bash
set -e # exit on error
# arguments
# -w 	<WORKSPACE_NAM> 	name of the workspace to be built and published
# -d 										carry out a dry run
# -t 	<TAG>							NPM tag, default value = latest
# -v <VERSION>					version to be published. default value = patch. Possible values: patch|minor|major|VERSION_NUMBER

# Example usage from npm scripts
# Add the following to package.jon to build and publish the package @swate/construct1 -
# "publish:construct1": "./scripts/publish.sh -w @myorg/mypkg1"
#
# Once the above script is added, it can be invoked from terminal with various arguments mentioned above:
# Here are some examples:
# Publish v1.2.0 of @myorg/pkg1 package with npm tag of "next": npm run publish:pkg1 -- -v 1.2.0 -t next
# Do a dry run of publishing patch version of @myorg/pkg1 package: npm run publish:pkg1 -- -d

source .env

# Check if the required environment variables have been set
if [[ -z "${DOMAIN_NAME}" ]] || [[ -z "${DOMAIN_OWNER}" ]] || [[ -z "${REGISTRY}" ]] || [[ -z "${REGION}" ]]; then
	echo "Please set the required environment variables: DOMAIN_NAME, DOMAIN_OWNER, REGISTRY, REGION"
	exit 1
fi

while getopts 'w:t:v:d' flag; do
    case "${flag}" in
        w) workspace=${OPTARG} ;;
        d) dryRun='--dry-run' ;;
        t) tag=${OPTARG} ;;
		v) version=${OPTARG} ;;
    esac
done
# default values for version and tag arguments if not provided in the command line arguments
: "${version:=patch}" "${tag:=latest}"

echo "Building and publishing $workspace"
# login to codeartifact
source ./scripts/login.sh
npm version $version -m "Upgrade to %s" --no-git-tag-version
npm publish -w $workspace $dryRun
```

A great security feature is to have a npm `preinstall` script to detect and mandate presence of project-local `.npmrc`

```json
"preinstall": "test -f .npmrc && exit 0 || echo '.npmrc does not exist. Please login to codeartifact' && exit 1",
```
