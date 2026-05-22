---
layout: ../layouts/GistLayout.astro
tags: [javascript, nodejs, guide]
---

# JavaScript (Node.js 24) Cheat Sheet

- [Variables & Types](#variables--types)
- [Numbers](#numbers)
- [Strings](#strings)
- [Arrays — Creating & Accessing](#arrays--creating--accessing)
- [Arrays — Mutating Methods](#arrays--mutating-methods)
- [Arrays — Non-Mutating Methods](#arrays--non-mutating-methods)
- [Arrays — Iteration](#arrays--iteration)
- [Objects](#objects)
- [Map & Set](#map--set)
- [Iterator Helpers (ES2025)](#iterator-helpers-es2025)
- [Functions](#functions)
- [Control Flow](#control-flow)
- [Error Handling](#error-handling)
- [Classes](#classes)
- [Promises & Async](#promises--async)
- [AbortController & Resource Management](#abortcontroller--resource-management)
- [Modules](#modules)
- [Regular Expressions](#regular-expressions)
- [JSON](#json)
- [Timers & Scheduling](#timers--scheduling)
- [Node.js Essentials](#nodejs-essentials)
- [Useful Global Methods](#useful-global-methods)

## Variables & Types

Use when declaring values, checking types, or safely accessing nested data.

```js
// Always use const (default) or let (reassignment needed) — never var
const name = 'Alice';
let count = 0;

// Primitive types: string, number, bigint, boolean, null, undefined, symbol
typeof 'hi'        // 'string'
typeof 42          // 'number'
typeof 42n         // 'bigint'
typeof true        // 'boolean'
typeof null        // 'object' (legacy quirk!)
typeof undefined   // 'undefined'
typeof Symbol()    // 'symbol'

// instanceof — check prototype chain
[] instanceof Array  // true
```

### Truthiness / Falsiness

| Falsy values             | Truthy (everything else)          |
|--------------------------|-----------------------------------|
| `false`                  | `true`                            |
| `0`, `-0`, `0n`         | Any non-zero number/bigint        |
| `''` (empty string)     | Any non-empty string (`'0'`, `'false'`) |
| `null`                   | `[]` (empty array)                |
| `undefined`              | `{}` (empty object)               |
| `NaN`                    | Any function                      |

```js
// Ternary
const label = count > 0 ? 'active' : 'idle';

// Nullish coalescing ?? — only null/undefined trigger fallback (not 0 or '')
const port = config.port ?? 3000;

// Optional chaining ?. — short-circuit on null/undefined
const zip = user?.address?.zip;
const first = arr?.[0];
const result = obj?.method?.();

// Destructuring — objects
const { name, age = 25, ...rest } = person;

// Destructuring — arrays
const [first, second, ...others] = items;

// Destructuring — nested with rename
const { address: { city, zip: zipCode = '00000' } } = user;

// Spread operator
const merged = { ...defaults, ...overrides };
const combined = [...arr1, ...arr2];
const copy = [...original];
```

## Numbers

Use when doing arithmetic, rounding, or working with large integers.

```js
// No separate int type — all numbers are 64-bit floats
0.1 + 0.2 === 0.3          // false! (floating point)
Number.isInteger(5.0)       // true
Number.isInteger(5.1)       // false
Math.trunc(4.9)             // 4 (drop decimal, don't round)
Number.MAX_SAFE_INTEGER     // 9007199254740991 (2^53 - 1)
Number.isSafeInteger(2**53) // false
```

| Math method       | Description                    | Example                     |
|-------------------|--------------------------------|-----------------------------|
| `Math.floor(x)`   | Round down                    | `Math.floor(4.7)` → `4`    |
| `Math.ceil(x)`    | Round up                      | `Math.ceil(4.1)` → `5`     |
| `Math.round(x)`   | Round to nearest              | `Math.round(4.5)` → `5`    |
| `Math.abs(x)`     | Absolute value                | `Math.abs(-3)` → `3`       |
| `Math.max(...xs)` | Largest value                 | `Math.max(1, 5, 3)` → `5`  |
| `Math.min(...xs)` | Smallest value                | `Math.min(1, 5, 3)` → `1`  |
| `Math.pow(b, e)`  | Exponentiation (`b**e`)       | `Math.pow(2, 3)` → `8`     |
| `Math.sqrt(x)`    | Square root                   | `Math.sqrt(16)` → `4`      |
| `Math.random()`   | Random float [0, 1)           | `Math.random()` → `0.482…` |
| `Math.sign(x)`    | -1, 0, or 1                  | `Math.sign(-5)` → `-1`     |
| `Math.hypot(a,b)` | Euclidean distance            | `Math.hypot(3, 4)` → `5`   |
| `Math.clz32(x)`   | Leading zeros (32-bit)       | `Math.clz32(1)` → `31`     |

```js
// Number methods
(3.14159).toFixed(2)   // '3.14' (returns string!)
parseInt('42px', 10)   // 42
parseFloat('3.14abc')  // 3.14

// BigInt — arbitrary precision integers
const big = 9007199254740993n;
big + 1n          // 9007199254740994n
// Cannot mix: big + 1 throws TypeError
```

## Strings

Use for text manipulation, formatting, and pattern matching.

| Method                         | Description                                    | Example                                      |
|--------------------------------|------------------------------------------------|----------------------------------------------|
| `s.split(sep)`                 | Split into array                              | `'a,b,c'.split(',')` → `['a','b','c']`      |
| `arr.join(sep)`                | Join array to string                          | `['a','b'].join('-')` → `'a-b'`             |
| `s.trim()`                     | Remove whitespace both ends                   | `' hi '.trim()` → `'hi'`                    |
| `s.trimStart()` / `trimEnd()`  | Remove whitespace one end                     | `' hi '.trimStart()` → `'hi '`              |
| `s.replace(pat, rep)`          | Replace first match                           | `'aab'.replace('a','x')` → `'xab'`          |
| `s.replaceAll(pat, rep)`       | Replace all matches                           | `'a-b-c'.replaceAll('-','_')` → `'a_b_c'`   |
| `s.includes(sub)`              | Contains substring?                           | `'hello'.includes('ell')` → `true`          |
| `s.startsWith(pre)`            | Starts with?                                  | `'hello'.startsWith('he')` → `true`         |
| `s.endsWith(suf)`              | Ends with?                                    | `'hello'.endsWith('lo')` → `true`           |
| `s.indexOf(sub)`               | First index of (-1 if none)                   | `'hello'.indexOf('l')` → `2`                |
| `s.lastIndexOf(sub)`           | Last index of                                 | `'hello'.lastIndexOf('l')` → `3`            |
| `s.at(i)`                      | Char at index (negative OK)                   | `'hello'.at(-1)` → `'o'`                    |
| `s.slice(start, end)`          | Extract substring (negative OK)               | `'hello'.slice(1, 3)` → `'el'`              |
| `s.substring(start, end)`      | Extract substring (no negatives)              | `'hello'.substring(1, 3)` → `'el'`          |
| `s.toUpperCase()`              | Upper case                                    | `'hi'.toUpperCase()` → `'HI'`               |
| `s.toLowerCase()`              | Lower case                                    | `'HI'.toLowerCase()` → `'hi'`               |
| `s.padStart(len, ch)`          | Pad from start                                | `'42'.padStart(5, '0')` → `'00042'`         |
| `s.padEnd(len, ch)`            | Pad from end                                  | `'hi'.padEnd(5, '.')` → `'hi...'`           |
| `s.repeat(n)`                  | Repeat n times                                | `'ab'.repeat(3)` → `'ababab'`               |

```js
// Template literals — multiline + expressions
const html = `
  <div class="${cls}">
    ${items.map(i => `<span>${i}</span>`).join('')}
  </div>`;

// Tagged template literal — custom processing
function sql(strings, ...vals) {
  return { text: strings.join('?'), params: vals };
}
const query = sql`SELECT * FROM users WHERE id = ${userId}`;

// matchAll with named groups
const re = /(?<year>\d{4})-(?<month>\d{2})/g;
for (const { groups } of '2024-01, 2025-06'.matchAll(re)) {
  console.log(groups.year, groups.month);
}

// Format numbers
(1234567.89).toLocaleString('en-US'); // '1,234,567.89'
new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(1234.5); // '$1,234.50'
```

## Arrays — Creating & Accessing

Use when building arrays or pulling values out of them.

```js
// Literals
const arr = [1, 2, 3];

// Array.from — from iterable or array-like, with optional map
Array.from({ length: 5 }, (_, i) => i * 2); // [0, 2, 4, 6, 8]
Array.from('hello');                         // ['h', 'e', 'l', 'l', 'o']

// Array.of — create from arguments (unlike Array(3) which creates empty slots)
Array.of(1, 2, 3); // [1, 2, 3]

// Fill
Array(5).fill(0);   // [0, 0, 0, 0, 0]

// Accessing
arr[0]              // 1
arr.at(-1)          // 3 (last element)
const [first, , third] = arr; // destructuring with skip

// Properties
arr.length          // 3
arr.includes(2)     // true
arr.indexOf(2)      // 1 (-1 if not found)
```

## Arrays — Mutating Methods

These modify the array in place. Use when performance matters or you own the array.

| Method                        | Description                                | Returns                |
|-------------------------------|--------------------------------------------|------------------------|
| `push(...items)`              | Add to end                                 | New length             |
| `pop()`                       | Remove from end                            | Removed element        |
| `unshift(...items)`           | Add to start                               | New length             |
| `shift()`                     | Remove from start                          | Removed element        |
| `splice(i, del, ...add)`     | Remove/insert at index                     | Array of removed items |
| `sort(compareFn)`             | Sort in place                              | Same array (sorted)    |
| `reverse()`                   | Reverse in place                           | Same array (reversed)  |
| `fill(val, start, end)`       | Fill with value                            | Same array (filled)    |
| `copyWithin(target, start, end)` | Copy within array                       | Same array             |

```js
// sort requires a comparator for numbers
[10, 1, 21].sort((a, b) => a - b); // [1, 10, 21]

// splice: at index 1, remove 2 items, insert 'a', 'b'
const arr = [1, 2, 3, 4];
arr.splice(1, 2, 'a', 'b'); // returns [2, 3]; arr is now [1, 'a', 'b', 4]
```

## Arrays — Non-Mutating Methods

These return new arrays/values. Prefer these for safety and chaining.

| Method                          | Description                                    | Returns              |
|---------------------------------|------------------------------------------------|----------------------|
| `map(fn)`                       | Transform each element                        | New array            |
| `filter(fn)`                    | Keep elements where fn is truthy              | New array            |
| `reduce(fn, init)`              | Accumulate to single value                    | Accumulated value    |
| `find(fn)`                      | First match                                   | Element or undefined |
| `findIndex(fn)`                 | Index of first match                          | Index or -1          |
| `findLast(fn)`                  | Last match                                    | Element or undefined |
| `findLastIndex(fn)`             | Index of last match                           | Index or -1          |
| `some(fn)`                      | Any match?                                    | Boolean              |
| `every(fn)`                     | All match?                                    | Boolean              |
| `flat(depth)`                   | Flatten nested arrays                         | New array            |
| `flatMap(fn)`                   | Map then flatten 1 level                      | New array            |
| `concat(...arrs)`               | Merge arrays                                  | New array            |
| `slice(start, end)`             | Extract portion                               | New array            |
| `join(sep)`                     | Join to string                                | String               |
| `includes(val)`                 | Contains value?                               | Boolean              |
| `indexOf(val)`                  | First index of value                          | Index or -1          |
| `toSorted(fn)`                  | Sorted copy (ES2023)                          | New array            |
| `toReversed()`                  | Reversed copy (ES2023)                        | New array            |
| `toSpliced(i, del, ...add)`    | Spliced copy (ES2023)                         | New array            |
| `with(index, value)`            | Copy with one element replaced (ES2023)       | New array            |
| `Array.from(iter, mapFn)`       | From iterable with optional map               | New array            |
| `Array.fromAsync(iter, mapFn)`  | From async iterable                           | Promise\<Array\>     |

```js
// Chaining
const result = data
  .filter(({ active }) => active)
  .map(({ name, score }) => ({ name, grade: score >= 90 ? 'A' : 'B' }))
  .toSorted((a, b) => a.name.localeCompare(b.name));

// toSpliced — non-mutating splice
[1, 2, 3, 4].toSpliced(1, 2, 'a'); // [1, 'a', 4]

// with — replace at index
[1, 2, 3].with(1, 'x'); // [1, 'x', 3]

// Array.fromAsync
const arr = await Array.fromAsync([Promise.resolve(1), Promise.resolve(2)]); // [1, 2]
```

## Arrays — Iteration

Use when looping through array contents.

```js
// for...of — iterate values (most common)
for (const item of items) { /* ... */ }

// for...of with entries() — get index + value
for (const [index, item] of items.entries()) { /* ... */ }

// forEach — no break/continue, returns undefined
items.forEach((item, index) => { /* ... */ });

// keys(), values(), entries()
[...items.keys()]    // [0, 1, 2, ...]
[...items.values()]  // same as [...items]
[...items.entries()] // [[0, 'a'], [1, 'b'], ...]

// Destructuring in sort/callbacks
points.sort(({ x: x1 }, { x: x2 }) => x1 - x2);
```

## Objects

Use for key-value data structures, transformation, and safe property access.

```js
// Object literals
const key = 'score';
const obj = {
  name: 'Alice',          // property shorthand (if var named 'name')
  [key]: 100,             // computed property name
  [`${key}Label`]: 'pts', // computed with template
  greet() { return `Hi, ${this.name}`; }, // method shorthand
};

// Object.keys / values / entries / fromEntries
Object.keys(obj)               // ['name', 'score', 'scoreLabel', 'greet']
Object.values(obj)             // ['Alice', 100, 'pts', [Function]]
Object.entries(obj)            // [['name','Alice'], ['score',100], ...]
Object.fromEntries([['a',1]]) // { a: 1 }

// Transform object values
const doubled = Object.fromEntries(
  Object.entries(obj).map(([k, v]) => [k, typeof v === 'number' ? v * 2 : v])
);

// Shallow copy / merge
Object.assign({}, obj, overrides)  // older style
const merged = { ...obj, ...overrides }; // spread (preferred)

// Deep copy
const clone = structuredClone(complexObj); // handles circular refs, Date, Map, Set

// Object.groupBy / Map.groupBy (ES2024)
Object.groupBy([1, 2, 3, 4], x => x % 2 === 0 ? 'even' : 'odd');
// { odd: [1, 3], even: [2, 4] }
Map.groupBy(items, ({ type }) => type); // Map with type keys

// Optional chaining
const zip = user?.address?.zip;

// Object.hasOwn() — preferred over obj.hasOwnProperty(key)
Object.hasOwn(obj, 'name'); // true
```

## Map & Set

Use Map for key-value pairs with any key type; Set for unique values.

```js
// Map — ordered, any key type, O(1) lookup
const m = new Map([['a', 1], ['b', 2]]);
m.set('c', 3);
m.get('a');      // 1
m.has('b');      // true
m.delete('a');   // true
m.size;          // 2
m.clear();       // remove all

// Iterate Map
for (const [key, val] of m) { /* ... */ }
[...m.keys()]    // all keys
[...m.values()]  // all values

// Set — unique values, O(1) lookup
const s = new Set([1, 2, 2, 3]); // Set {1, 2, 3}
s.add(4);        // Set {1, 2, 3, 4}
s.has(2);        // true
s.delete(1);     // true
s.size;          // 3
```

### Set Methods (ES2025)

```js
const a = new Set([1, 2, 3, 4]);
const b = new Set([3, 4, 5, 6]);

a.union(b);               // Set {1, 2, 3, 4, 5, 6}
a.intersection(b);        // Set {3, 4}
a.difference(b);          // Set {1, 2}
a.symmetricDifference(b); // Set {1, 2, 5, 6}

new Set([1, 2]).isSubsetOf(a);     // true
a.isSupersetOf(new Set([1, 2]));   // true
a.isDisjointFrom(new Set([7, 8])); // true
```

### WeakMap & WeakSet

```js
// WeakMap — keys must be objects, allows garbage collection
// Use for: private data, caching without memory leaks
const wm = new WeakMap();
wm.set(obj, 'metadata');
wm.get(obj); // 'metadata' — gone when obj is GC'd

// WeakSet — same idea but for tracking object membership
const visited = new WeakSet();
visited.add(node);
visited.has(node); // true
```

## Iterator Helpers (ES2025)

Use for lazy, memory-efficient processing of sequences without creating intermediate arrays.

```js
// Iterator.from — wrap any iterable into an iterator with helper methods
const iter = Iterator.from([1, 2, 3, 4, 5, 6, 7, 8]);

// Lazy .filter(), .map(), .take(), .drop() — no intermediate arrays!
iter.filter(x => x % 2 === 0).map(x => x * 10).take(2).toArray(); // [20, 40]

// .drop() — skip first N
Iterator.from([1, 2, 3, 4]).drop(2).toArray(); // [3, 4]

// .flatMap()
Iterator.from([1, 2, 3]).flatMap(x => [x, -x]).toArray(); // [1, -1, 2, -2, 3, -3]

// .reduce()
Iterator.from([1, 2, 3, 4]).reduce((sum, x) => sum + x, 0); // 10

// .some(), .every(), .find()
Iterator.from([1, 2, 3]).some(x => x > 2);  // true
Iterator.from([1, 2, 3]).every(x => x > 0); // true
Iterator.from([1, 2, 3]).find(x => x > 1);  // 2

// .forEach()
Iterator.from([1, 2, 3]).forEach(x => console.log(x));
```

## Functions

Use for reusable logic, closures, and generators.

```js
// Arrow function (lexical `this`, no own `arguments`)
const add = (a, b) => a + b;
const getObj = () => ({ key: 'val' }); // parens needed to return object literal

// Function declaration (hoisted, has own `this`)
function greet(name) { return `Hello, ${name}`; }

// Default params (can reference earlier params)
function range(start, end, step = start < end ? 1 : -1) { /* ... */ }

// Rest params — collects remaining args into array
function sum(...nums) { return nums.reduce((a, b) => a + b, 0); }

// Closure — function retains access to its creation scope
function memoize(fn) {
  const cache = new Map();
  return (...args) => {
    const key = JSON.stringify(args);
    if (!cache.has(key)) cache.set(key, fn(...args));
    return cache.get(key);
  };
}

// IIFE — immediately invoked function expression
const config = (() => {
  const env = process.env;
  return { port: env.PORT || 3000 };
})();

// Generator function — lazy sequences
function* range(start, end) {
  for (let i = start; i < end; i++) yield i;
}
[...range(0, 5)] // [0, 1, 2, 3, 4]

// yield* — delegate to another iterable/generator
function* concat(...iters) {
  for (const it of iters) yield* it;
}
```

## Control Flow

Use for branching, looping, and iteration patterns.

```js
// if / else if / else
if (x > 10) { /* ... */ }
else if (x > 5) { /* ... */ }
else { /* ... */ }

// switch — don't forget break!
switch (action) {
  case 'start': start(); break;
  case 'stop': stop(); break;
  default: throw new Error(`Unknown: ${action}`);
}

// for...of — iterate any iterable (arrays, strings, Maps, Sets, generators)
for (const item of iterable) { /* ... */ }

// for...in — iterate object's own + inherited enumerable keys (usually avoid)
for (const key in obj) { if (Object.hasOwn(obj, key)) { /* ... */ } }

// while / do...while
while (condition) { /* ... */ }
do { /* at least once */ } while (condition);

// break / continue
for (const item of items) {
  if (item.skip) continue; // skip this iteration
  if (item.done) break;    // exit loop entirely
}

// Labeled statements — break/continue outer loops
outer: for (const row of matrix) {
  for (const cell of row) {
    if (cell === target) break outer;
  }
}

// try / catch / finally
try { riskyOp(); }
catch (err) { handleError(err); }
finally { cleanup(); } // always runs
```

## Error Handling

Use for creating, throwing, and chaining errors with proper context.

```js
// Built-in error types
throw new Error('Something went wrong');
throw new TypeError('Expected a string');
throw new RangeError('Index out of bounds');

// Error cause — chain errors for debugging
try { fetchData(); }
catch (e) { throw new Error('Load failed', { cause: e }); }

// Custom error class
class ValidationError extends Error {
  constructor(field, message) {
    super(message);
    this.name = 'ValidationError';
    this.field = field;
  }
}

// AggregateError — wrap multiple errors
const errors = [new Error('a'), new Error('b')];
throw new AggregateError(errors, 'Multiple failures');
// catch: err.errors → [Error('a'), Error('b')]
```

## Classes

Use for encapsulated state, inheritance, and object-oriented patterns.

```js
class Cache {
  // Private fields (not accessible outside class)
  #store = new Map();
  #maxSize;

  // Static field + method
  static DEFAULT_SIZE = 100;
  static create(size) { return new Cache(size); }

  constructor(maxSize = Cache.DEFAULT_SIZE) {
    this.#maxSize = maxSize;
  }

  // Getter / Setter
  get size() { return this.#store.size; }
  set max(n) { this.#maxSize = n; }

  // Private method
  #evict() {
    const first = this.#store.keys().next().value;
    this.#store.delete(first);
  }

  put(k, v) {
    if (this.#store.size >= this.#maxSize) this.#evict();
    this.#store.set(k, v);
  }
}

// Inheritance
class LRUCache extends Cache {
  constructor(size) {
    super(size); // must call super before using `this`
  }
  // Override or extend methods
}

// instanceof
new Cache() instanceof Cache; // true
```

## Promises & Async

Use for asynchronous operations, concurrency, and non-blocking I/O.

```js
// Creating a promise
const p = new Promise((resolve, reject) => {
  doAsyncWork((err, result) => {
    if (err) reject(err);
    else resolve(result);
  });
});

// async/await — preferred pattern
async function loadData() {
  try {
    const response = await fetch(url);
    const data = await response.json();
    return data;
  } catch (err) {
    console.error('Failed:', err.message);
    throw err;
  }
}
```

| Combinator              | Resolves when                         | Rejects when                         |
|-------------------------|---------------------------------------|--------------------------------------|
| `Promise.all(ps)`       | All fulfill                          | First rejection (fail-fast)          |
| `Promise.allSettled(ps)` | All settle (fulfill or reject)      | Never rejects                        |
| `Promise.any(ps)`       | First fulfillment                    | All reject (AggregateError)          |
| `Promise.race(ps)`      | First settlement (fulfill or reject) | First settlement is a rejection      |

```js
// Promise.all — parallel, fail-fast
const [a, b] = await Promise.all([fetchA(), fetchB()]);

// Promise.allSettled — get all results regardless of failures
const results = await Promise.allSettled([p1, p2]);
results.filter(r => r.status === 'fulfilled').map(r => r.value);

// Promise.any — first success
const fastest = await Promise.any([mirror1(), mirror2()]);

// Promise.race — first to settle (use for timeouts)
const winner = await Promise.race([fetchData(), timeout(5000)]);

// Promise.withResolvers (ES2024) — externalize resolve/reject
const { promise, resolve, reject } = Promise.withResolvers();
setTimeout(() => resolve('done'), 1000);

// Promise.try (ES2025) — wrap sync/async uniformly in a promise
const result = await Promise.try(() => maybeSyncOrAsync());

// Error handling with await
async function safe() {
  try { return await riskyOp(); }
  catch (err) { return fallback; }
}

// for await...of — async iteration
async function* fetchPages(urls) {
  for (const url of urls) yield await fetch(url);
}
for await (const response of fetchPages(urls)) { /* ... */ }
```

## AbortController & Resource Management

Use for cancellation, timeouts, and deterministic cleanup.

```js
// AbortController — cancel async operations
const controller = new AbortController();
fetch(url, { signal: controller.signal });
controller.abort(); // cancels the fetch

// AbortSignal.timeout — auto-abort after duration
await fetch(url, { signal: AbortSignal.timeout(5000) });

// AbortSignal.any — abort when ANY signal fires
const signal = AbortSignal.any([
  controller.signal,
  AbortSignal.timeout(10000),
]);

// Explicit Resource Management (ES2024) — using / await using
class Connection {
  [Symbol.dispose]() { this.close(); }
}
{
  using conn = new Connection();
  // conn is auto-disposed at end of block
}

class AsyncConn {
  async [Symbol.asyncDispose]() { await this.close(); }
}
{
  await using conn = new AsyncConn();
  // conn is auto-disposed (awaited) at end of block
}
```

## Modules

Use for organizing code into reusable, importable units.

```js
// Named exports
export const PI = 3.14;
export function add(a, b) { return a + b; }

// Named imports
import { add, PI } from './math.js';

// Default export
export default class MyService { /* ... */ }

// Default import
import MyService from './service.js';

// Mixed
import MyService, { helper } from './service.js';

// Rename on import/export
export { foo as default, bar as baz };
import { default as Foo, baz } from './mod.js';

// Dynamic import — lazy loading, conditional
const { helper } = await import(`./plugins/${name}.js`);

// import.meta (Node.js)
import.meta.url       // 'file:///path/to/module.js'
import.meta.dirname   // '/path/to' (replaces __dirname)
import.meta.filename  // '/path/to/module.js' (replaces __filename)
```

## Regular Expressions

Use for pattern matching, validation, and text extraction.

| Pattern         | Matches                              |
|-----------------|--------------------------------------|
| `\d` / `\D`    | Digit / Non-digit                   |
| `\w` / `\W`    | Word char [a-zA-Z0-9_] / Non-word  |
| `\s` / `\S`    | Whitespace / Non-whitespace         |
| `.`             | Any char (except newline by default)|
| `*` / `+` / `?`| 0+, 1+, 0 or 1 (greedy)           |
| `*?` / `+?`    | Non-greedy versions                 |
| `{n}` / `{n,m}`| Exactly n / Between n and m         |
| `^` / `$`      | Start / End of string (or line with `m`) |
| `[abc]` / `[^abc]` | Character class / Negated class |
| `(...)` / `(?:...)` | Capturing group / Non-capturing |
| `(?<name>...)`  | Named capturing group              |
| `a|b`           | Alternation                         |
| `(?=...)` / `(?!...)` | Lookahead / Negative lookahead |
| `(?<=...)` / `(?<!...)` | Lookbehind / Negative lookbehind |

| Flag | Description                                  |
|------|----------------------------------------------|
| `g`  | Global — find all matches                   |
| `i`  | Case-insensitive                            |
| `m`  | Multiline — `^`/`$` match line boundaries  |
| `s`  | Dotall — `.` matches newlines too           |
| `d`  | Indices — include start/end positions       |
| `v`  | UnicodeSets (ES2024) — set notation in `[]` |

```js
// test — boolean match
/^\d{3}$/.test('123'); // true

// exec — detailed single match
const m = /(?<year>\d{4})-(?<month>\d{2})/.exec('2025-06-15');
m.groups.year; // '2025'

// match — array of matches (with g) or first match (without g)
'a1 b2 c3'.match(/\d/g); // ['1', '2', '3']

// matchAll — iterator of all matches with groups
const matches = [...'a1 b2'.matchAll(/(?<l>[a-z])(?<d>\d)/g)];
matches[0].groups; // { l: 'a', d: '1' }

// replace / replaceAll with regex
'2025-06-15'.replace(/(\d{4})-(\d{2})-(\d{2})/, '$3/$2/$1'); // '15/06/2025'

// search — index of first match (-1 if none)
'hello world'.search(/world/); // 6

// split with regex
'one1two2three'.split(/\d/); // ['one', 'two', 'three']

// Lookbehind
'$100 EUR200'.match(/(?<=\$)\d+/);  // ['100'] — preceded by $
'$100 EUR200'.match(/(?<!\$)\d+/);  // ['200'] — NOT preceded by $
```

## JSON

Use for serialization, data exchange, and configuration.

```js
// Parse string → object
const obj = JSON.parse('{"a":1,"b":"hi"}');

// Stringify object → string
JSON.stringify(obj);              // '{"a":1,"b":"hi"}'
JSON.stringify(obj, null, 2);    // pretty-printed with 2-space indent

// Reviver — transform values during parse
JSON.parse(json, (key, val) => key === 'date' ? new Date(val) : val);

// Replacer — filter/transform during stringify
JSON.stringify(obj, (key, val) => key === 'password' ? undefined : val);
JSON.stringify(obj, ['name', 'age']); // only include these keys

// structuredClone vs JSON round-trip
// structuredClone: handles Date, Map, Set, ArrayBuffer, circular refs
// JSON: loses Date (becomes string), drops undefined, no Map/Set, no circular
const deepCopy = structuredClone(obj); // preferred for deep clone
```

## Timers & Scheduling

Use for delays, intervals, and microtask scheduling.

```js
// setTimeout / clearTimeout
const id = setTimeout(() => console.log('delayed'), 1000);
clearTimeout(id); // cancel

// setInterval / clearInterval
const id = setInterval(() => poll(), 5000);
clearInterval(id); // stop

// Node.js promisified timers (preferred in async code)
import { setTimeout, setInterval } from 'node:timers/promises';

await setTimeout(1000); // simple delay
const val = await setTimeout(1000, 'result'); // resolves with 'result'

// Abortable timer
await setTimeout(1000, null, { signal: AbortSignal.timeout(5000) });

// Async interval
for await (const _ of setInterval(1000, null, { signal: controller.signal })) {
  // runs every 1s until aborted
}

// Microtask — runs before next macrotask (setTimeout, I/O)
queueMicrotask(() => console.log('microtask'));

// process.nextTick (Node.js) — runs before microtasks (use sparingly)
process.nextTick(() => console.log('next tick'));
```

## Node.js Essentials

Use for common Node.js-specific patterns and APIs.

```js
// util.promisify — wrap callback-style APIs
import { promisify } from 'node:util';
import fs from 'node:fs';
const readFile = promisify(fs.readFile);

// crypto.randomUUID
import { randomUUID } from 'node:crypto';
const id = randomUUID(); // 'a1b2c3d4-e5f6-...'

// process.env — environment variables
const port = process.env.PORT || 3000;

// process.argv — command-line arguments
// ['node', '/path/to/script.js', 'arg1', 'arg2']
const [,, ...args] = process.argv;

// Buffer — binary data
const buf = Buffer.from('hello', 'utf-8');
buf.toString('base64');    // 'aGVsbG8='
Buffer.from('aGVsbG8=', 'base64').toString('utf-8'); // 'hello'

// EventEmitter pattern
import { EventEmitter } from 'node:events';
class MyService extends EventEmitter {
  process(data) {
    this.emit('start', data);
    // ... work ...
    this.emit('done', result);
  }
}
const svc = new MyService();
svc.on('done', result => console.log(result));
svc.once('error', err => console.error(err)); // listen once
```

## Useful Global Methods

Quick reference for commonly needed global/built-in utilities.

| Method / Property              | Description                              | Example                                 |
|--------------------------------|------------------------------------------|-----------------------------------------|
| `parseInt(str, radix)`         | Parse string to integer                 | `parseInt('0xFF', 16)` → `255`          |
| `parseFloat(str)`              | Parse string to float                   | `parseFloat('3.14')` → `3.14`           |
| `isNaN(val)`                   | Coerces then checks NaN (use Number.isNaN) | `isNaN('hi')` → `true`              |
| `Number.isNaN(val)`            | Strict NaN check (no coercion)          | `Number.isNaN('hi')` → `false`          |
| `Number.isFinite(val)`         | Is finite number? (no coercion)         | `Number.isFinite(Infinity)` → `false`   |
| `Number.isInteger(val)`        | Is integer?                             | `Number.isInteger(5.0)` → `true`        |
| `encodeURIComponent(str)`      | Encode for URL query param              | `encodeURIComponent('a&b')` → `'a%26b'` |
| `decodeURIComponent(str)`      | Decode URL-encoded string               | `decodeURIComponent('a%26b')` → `'a&b'` |
| `structuredClone(obj)`         | Deep clone (handles complex types)      | `structuredClone({a: [1]})` → `{a: [1]}` |
| `crypto.randomUUID()`          | Generate UUID v4                        | `crypto.randomUUID()` → `'a1b2...'`    |
| `atob(str)` / `btoa(str)`     | Base64 decode / encode                  | `btoa('hi')` → `'aGk='`                |
| `queueMicrotask(fn)`           | Schedule microtask                      | Runs before next I/O                    |
