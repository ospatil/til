---
layout: ../layouts/GistLayout.astro
tags: [haskell]
---

# Tracing a haskell program

Haskell - tracing a program

```haskell
module Main where

import Debug.Trace

factorial n = go n 1  
	where
		go n acc
			| n > 1 = trace ("n = " ++ show n ++ ", acc = " ++ show acc) (go (n - 1) (acc * n))
			| otherwise = acc

main :: IO ()
main = do
	print (factorial 3)
```
