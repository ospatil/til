---
layout: ../layouts/GistLayout.astro
tags: [svelte, sveltekit, aws, lambda, guide]
---

# Deploying SvelteKit SSR on AWS Lambda

## Main Components

- CloudFront with 2 origins, both protected by OAC
  - S3 origin for static content
  - Lambda function URL origin
- S3 bucket for static content
- Lambda that hosts the SvelteKit SSR backend (deployed in VPC to connect to RDS)
- Cognito user pool for user authentication
- RDS Postgres database
- SvelteKit application using `paraglidejs` for i18n and `drizzleorm`

## Application Details

The app is under `<WORKSPACE_ROOT>/app/myapp` and the CDK code is under `<WORKSPACE_ROOT>/arch`.

### Key Scripts

```json
"dev": "npm-run-all --parallel build:paraglide vite",
"build:paraglide": "paraglide-js compile --project ./project.inlang --outdir ./src/paraglide",
"build": "npm run build:paraglide && vite build",
"bundle": "npm run build && node scripts/bundle.js",
"preview": "source .env.local && vite preview",
"migrate:gen": "drizzle-kit generate --dialect postgresql --schema=./src/lib/schemas/schema.ts --out=./migrator/migrations",
"migrate:bundle": "esbuild migrator/index.ts --outfile=migrator/main.mjs --bundle --platform=node --target=esnext --format=esm --banner:js=\"import { createRequire as topLevelCreateRequire } from 'node:module';const require = topLevelCreateRequire(import.meta.url);\"",
"migrate:local": "npm run migrate:bundle && cd migrator && node --env-file=../.env.local local-runner.mjs",
"db:local": "docker run -d --rm -e POSTGRES_USER=dbadmin -e POSTGRES_PASSWORD=postgresadmin -p 5432:5432 -v app-data:/var/lib/postgresql/data --name postgres postgres",
"postinstall": "paraglide-js compile --project ./project.inlang --outdir ./src/paraglide"
```

The application uses `sveltekit-lambda-adapter` for packaging:

```js
// scripts/bundle.js
import { bundleApp } from 'sveltekit-lambda-adapter'
bundleApp()
```

### Database Migrations

Migrations are generated in `./migrator/migrations`, bundled and run as Lambda in AWS. They can also be run locally using `migrate:local`.

**migrator/index.ts** (Lambda entrypoint):

```ts
import * as process from 'node:process'
import { sql } from 'drizzle-orm'
import { drizzle } from 'drizzle-orm/postgres-js'
import { migrate } from 'drizzle-orm/postgres-js/migrator'
import postgres from 'postgres'
import { getConnectionOptions, readEnvVariables } from '../src/lib/server/db-utils'

export async function handler(_event: any) {
  const dbVars = readEnvVariables(process.env)
  const connectOpts = await getConnectionOptions(dbVars)
  const connection = postgres('', connectOpts)
  const db = drizzle(connection)

  const grantStmt = sql.raw(`
    GRANT USAGE ON SCHEMA public TO ${dbVars.appDbUser};
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${dbVars.appDbUser};
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO ${dbVars.appDbUser};
  `)
  await db.execute(grantStmt)

  await migrate(db, { migrationsFolder: 'migrations' })
  await connection.end()
  console.log(`Migrations applied successfully`)
}
```

### DB Connection Utilities

**db-utils.ts** - handles both local (password) and AWS (IAM RDS Signer) authentication:

```ts
import { Signer } from '@aws-sdk/rds-signer'

export type DbEnvVars = {
  host: string
  port: number
  user: string
  database: string
  password?: string
  appDbUser?: string
}

export function readEnvVariables(env: any) {
  return {
    host: env.RDS_DB_RW_ENDPOINT!,
    port: Number(env.RDS_DB_PORT!),
    user: env.RDS_DB_USER!,
    database: env.RDS_DB_NAME!,
    password: env.LOCAL_DB_PASSWORD,
    appDbUser: env.APP_DB_USER,
  }
}

export async function getConnectionOptions(envVars: DbEnvVars) {
  const { host, port, database, user, password } = envVars
  let signer: Signer

  if (!password) {
    signer = new Signer({ hostname: host, username: user, port })
  }

  return {
    host, port, database, user,
    password: password ?? (async () => await signer.getAuthToken()),
    idle_timeout: 20,
    max_lifetime: 60 * 5,
    ssl: !password,
  }
}
```

**db.ts** - application connection:

```ts
import { env } from '$env/dynamic/private'
import * as schema from '$lib/schemas/schema'
import { drizzle } from 'drizzle-orm/postgres-js'
import postgres from 'postgres'
import { getConnectionOptions, readEnvVariables } from './db-utils'

const connectOpts = await getConnectionOptions(readEnvVariables(env))
const connection = postgres('', connectOpts)
export const db = drizzle(connection, { schema })
```

> Since db.ts is a separate file, you can import it in a `queries.ts` and test queries directly with vitest.

### Authentication - hooks.server.ts

```ts
import type { Handle, HandleServerError } from '@sveltejs/kit'
import { handleProtectedRoute } from '$lib/auth/auth'
import { logger } from '$lib/server/logger'

const openRouteIds = ['/']

export const handleError: HandleServerError = ({ status, error, message }) => {
  if (status !== 404) logger.error(error)
  return { message }
}

export const handle: Handle = async ({ event, resolve }) => {
  if (!openRouteIds.some(ending => event?.route?.id?.endsWith(ending))) {
    return handleProtectedRoute(event, resolve)
  }
  return resolve(event)
}
```

### Cognito JWT Verification

```ts
import { env } from '$env/dynamic/public'
import { redirect } from '@sveltejs/kit'
import { CognitoJwtVerifier } from 'aws-jwt-verify/cognito-verifier'

async function validateToken(token: string, tokenUse: 'access' | 'id'): Promise<boolean> {
  try {
    const verifier = CognitoJwtVerifier.create({
      userPoolId: env.PUBLIC_COGNITO_USER_POOL_ID,
    })
    await verifier.verify(token, {
      clientId: env.PUBLIC_COGNITO_USER_POOL_CLIENT_ID,
      tokenUse,
    })
    return true
  } catch (err) {
    return false
  }
}

export async function handleProtectedRoute(event: any, resolve: any) {
  if (await userIsValid(event?.locals, event?.cookies)) {
    if (event?.route.id === '/') return redirect(302, '/dashboard')
    return resolve(event)
  }
  return redirect(302, '/')
}
```

### Amplify Configuration with CookieStorage

```ts
import { browser } from '$app/environment'
import { env } from '$env/dynamic/public'
import { Amplify } from 'aws-amplify'
import { cognitoUserPoolsTokenProvider } from 'aws-amplify/auth/cognito'
import { CookieStorage } from 'aws-amplify/utils'

if (browser) {
  Amplify.configure({
    Auth: {
      Cognito: {
        userPoolId: env.PUBLIC_COGNITO_USER_POOL_ID!,
        userPoolClientId: env.PUBLIC_COGNITO_USER_POOL_CLIENT_ID!,
        loginWith: {
          oauth: {
            domain: env.PUBLIC_COGNITO_DOMAIN!,
            scopes: ['aws.cognito.signin.user.admin', 'email', 'openid', 'profile'],
            redirectSignIn: [env.PUBLIC_PRIMARY_DOMAIN ?? 'http://localhost:5173'],
            redirectSignOut: [env.PUBLIC_PRIMARY_DOMAIN ?? 'http://localhost:5173'],
            responseType: 'code',
          },
        },
      },
    },
  })
  cognitoUserPoolsTokenProvider.setKeyValueStorage(new CookieStorage())
}
```

### OAC - Signing API Requests

Since CloudFront OAC protects the SSR Lambda, API requests need SHA256 signing:

```ts
import { Sha256 } from '@aws-crypto/sha256-browser'
import { fetchAuthSession } from 'aws-amplify/auth'

export async function prefetch(payload?: any): Promise<{ headers: Headers }> {
  await fetchAuthSession({ forceRefresh: true })

  if (payload) {
    const sha256 = new Sha256()
    sha256.update(payload, 'utf8')
    const hash = await sha256.digest()
    const encodedHash = Array.from(new Uint8Array(hash))
      .map(b => b.toString(16).padStart(2, '0')).join('')
    return { headers: { 'X-Amz-Content-Sha256': encodedHash, 'Accept': '*/*' } }
  }
  return { headers: { 'Content-Type': 'application/json' } }
}
```

Usage:
- GET: `await prefetch()` - just refreshes session
- POST JSON: `const { headers } = await prefetch(JSON.stringify(body))`
- POST FormData: compute SHA256 of URL-encoded payload

### SvelteKit Config

```js
import { adapter } from 'sveltekit-lambda-adapter'
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte'

const config = {
  preprocess: [vitePreprocess()],
  kit: {
    csp: {
      mode: 'auto',
      directives: {
        'default-src': ['self'],
        'script-src': ['nonce', 'strict-dynamic', 'self', 'https:', 'unsafe-inline'],
        'connect-src': ['self', 'cognito-idp.ca-central-1.amazonaws.com',
          '*.auth.ca-central-1.amazoncognito.com/oauth2/token'],
        'style-src': ['self', 'nonce', 'unsafe-inline'],
      },
    },
    csrf: {
      // Required: request.url.origin has Lambda URL while origin header has primary domain
      checkOrigin: false,
    },
    adapter: adapter(),
  },
}
export default config
```

## CDK Infrastructure

### SSR Lambda

```ts
const ssrLambda = new lambda.Function(this, `${app}-SsrLambda`, {
  handler: 'index.handler',
  memorySize: 2048,
  runtime: lambda.Runtime.NODEJS_20_X,
  code: lambda.Code.fromAsset(path.join(__dirname, '../../app/my-app/build')),
  timeout: cdk.Duration.minutes(1),
  tracing: lambda.Tracing.ACTIVE,
  vpc: props.network.vpc,
  vpcSubnets: props.network.appSubnets,
  securityGroups: [props.network.appSecurityGroup],
  environment: {
    PUBLIC_COGNITO_USER_POOL_ID: userPoolId,
    PUBLIC_COGNITO_USER_POOL_CLIENT_ID: userPoolClientId,
    PUBLIC_COGNITO_DOMAIN: cognitoUserPoolDomain,
    PUBLIC_PRIMARY_DOMAIN: primaryDomain,
    RDS_DB_RW_ENDPOINT: appDb.proxy.proxy.endpoint,
    RDS_DB_NAME: appDb.dbName,
    RDS_DB_USER: appDb.databaseUsers.app,
    RDS_DB_PORT: appDb.port,
  },
  loggingFormat: lambda.LoggingFormat.JSON,
})

appDb.proxy.proxy.grantConnect(ssrLambda, '*')
```

### Function URL + CloudFront

```ts
const ssrFnAlias = ssrLambda.addAlias('prod')
const ssrLambdaUrl = ssrFnAlias.addFunctionUrl({
  authType: lambda.FunctionUrlAuthType.AWS_IAM,
})

// CloudFront with S3 + Lambda origins
distribution.addBehavior('/_app/immutable/*', s3Origin)
distribution.addBehavior('/resources/*', s3Origin)
distribution.addBehavior('/*', new origins.FunctionUrlOrigin(ssrLambdaUrl), {
  cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
  originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER_EXCEPT_HOST_HEADER,
  allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
  viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
})

// OAC for Lambda
const ssrLambdaOac = new cloudfront.CfnOriginAccessControl(this, 'SsrLambdaOac', {
  originAccessControlConfig: {
    name: 'SsrLambdaOac',
    originAccessControlOriginType: 'lambda',
    signingBehavior: 'always',
    signingProtocol: 'sigv4',
  },
})

// Allow CloudFront to invoke Lambda
ssrFnAlias.addPermission('AllowCloudFront', {
  principal: new iam.ServicePrincipal('cloudfront.amazonaws.com'),
  action: 'lambda:InvokeFunctionUrl',
  sourceArn: `arn:aws:cloudfront::${cdk.Aws.ACCOUNT_ID}:distribution/${distribution.distributionId}`,
})
```

---

## VS Code Workspace Setup

### Recommended Extensions

```json
{
  "recommendations": [
    "svelte.svelte-vscode",
    "dbaeumer.vscode-eslint",
    "ardenivanov.svelte-intellisense",
    "fivethree.vscode-svelte-snippets",
    "pivaszbs.svelte-autoimport",
    "bradlc.vscode-tailwindcss",
    "stivo.tailwind-fold",
    "inlang.vs-code-extension"
  ]
}
```

### Workspace Settings

ESLint flat config with styling rules silenced (auto-fixed on save), Tailwind class attributes for component libraries, and SvelteKit file labels for easier tab navigation:

```json
{
  "eslint.useFlatConfig": true,
  "prettier.enable": false,
  "editor.formatOnSave": false,
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": "explicit",
    "source.organizeImports": "never"
  },
  "eslint.rules.customizations": [
    { "rule": "style/*", "severity": "off" },
    { "rule": "format/*", "severity": "off" },
    { "rule": "*-indent", "severity": "off" },
    { "rule": "*-spacing", "severity": "off" },
    { "rule": "*-spaces", "severity": "off" },
    { "rule": "*-order", "severity": "off" },
    { "rule": "*-dangle", "severity": "off" },
    { "rule": "*-newline", "severity": "off" },
    { "rule": "*quotes", "severity": "off" },
    { "rule": "*semi", "severity": "off" }
  ],
  "eslint.validate": [
    "javascript", "javascriptreact", "typescript", "typescriptreact",
    "vue", "html", "markdown", "json", "jsonc", "yaml", "toml", "astro", "svelte"
  ],
  "workbench.editor.customLabels.patterns": {
    "**/src/routes/**/+layout.svelte": "${dirname} - Layout",
    "**/src/routes/**/+layout.server.ts": "${dirname} - Layout Server",
    "**/src/routes/**/+page.svelte": "${dirname} - Page",
    "**/src/routes/**/+page.server.ts": "${dirname} - Page Server",
    "**/src/routes/**/+page.ts": "${dirname} - Page Load",
    "**/src/routes/**/+error.svelte": "${dirname} - Error",
    "**/src/routes/**/+layout.ts": "${dirname} - Layout Load"
  }
}
```

### ESLint Config (Antfu + Tailwind + Svelte)

```js
import antfu from '@antfu/eslint-config'
import { FlatCompat } from '@eslint/eslintrc'

const compat = new FlatCompat()

export default antfu({
  ignores: [
    '**/*/package-lock.json',
    '**/*/*.d.ts',
    'app/my-app/src/lib/components/ui/**/*',
    'app/my-app/src/paraglide/**/*',
    'app/my-app/migrator/**/*.json',
  ],
  formatters: true,
  yaml: false,
  svelte: true,
}, ...compat.config({
  extends: ['plugin:tailwindcss/recommended'],
  rules: {
    'tailwindcss/classnames-order': 'error',
    'tailwindcss/no-custom-classname': 'error',
  },
}), {
  rules: {
    'curly': ['error', 'all'],
    'style/brace-style': ['error', 'stroustrup', { allowSingleLine: false }],
    'unused-imports/no-unused-vars': ['warn'],
  },
})
```
