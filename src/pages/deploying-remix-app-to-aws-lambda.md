---
layout: ../layouts/GistLayout.astro
tags: [aws,lambda,react,remix]
---

# Deploying remix app to AWS Lambda

AWS Adapter for remix - [https://github.com/wingleung/remix-aws](https://github.com/wingleung/remix-aws)

Here is the `vite.config.ts` file with the adapter configuration

```tsx
import { Preset, vitePlugin as remix } from "@remix-run/dev";
import { defineConfig } from "vite";
import tsconfigPaths from "vite-tsconfig-paths";
import { awsPreset, AWSProxy } from 'remix-aws'

export default defineConfig({
  plugins: [
    remix({
      serverBuildFile: 'index.mjs',
      ignoredRouteFiles: ["**/*.css"],
      presets: [
        awsPreset({
          awsProxy: AWSProxy.FunctionURL,

          // additional esbuild configuration
          build: {
            minify: true,
            treeShaking: true,
            bundle: true,
            sourcemap: true,
            // format: 'esm',
            // target: 'es2022',
            // platform: 'node',
          }
        }) as Preset
      ]
    }),
    tsconfigPaths(),
  ],
});

```
