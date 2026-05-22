---
layout: ../layouts/GistLayout.astro
tags: [golang, guide]
---

# Go 1.26 Cheat Sheet

- [Variables & Types](#variables--types)
- [Numbers](#numbers)
- [Strings](#strings)
- [Slices](#slices)
- [Maps](#maps)
- [Structs](#structs)
- [Interfaces](#interfaces)
- [Control Flow](#control-flow)
- [Functions](#functions)
- [Error Handling](#error-handling)
- [Generics](#generics)
- [Concurrency](#concurrency)
- [Iteration (1.22+)](#iteration-122)
- [Testing](#testing)
- [I/O & Files](#io--files)
- [JSON](#json)
- [Common Patterns](#common-patterns)
- [Useful Standard Library](#useful-standard-library)

## Variables & Types

> Foundation of every Go program — declaring, converting, and pointing to values.

```go
// Declaration
var name string              // zero value: ""
var x, y int = 1, 2         // explicit type
count := 10                  // short declaration (inferred type, only inside functions)
const Pi = 3.14159           // untyped constant
const MaxSize int = 1024     // typed constant

// Pointers
p := &count                  // address-of
fmt.Println(*p)              // dereference (10)
ptr := new(int)              // allocates zero-valued int, returns *int
```

**Zero values table**

| Type | Zero value |
|------|-----------|
| int, float64 | `0` |
| string | `""` |
| bool | `false` |
| pointer, slice, map, chan, func, interface | `nil` |

**Type conversions** (Go never converts implicitly):

```go
i := int(3.9)               // 3 (truncates)
f := float64(i)             // 3.0
s := string(rune(65))       // "A"
b := []byte("hello")        // UTF-8 bytes
r := []rune("hello")        // Unicode code points
s = string(b)               // bytes -> string
n := int64(i)               // widen
```

---

## Numbers

> Arithmetic, math utilities, and converting between numbers and strings.

**Integer types**: `int` (platform-sized), `int8`, `int16`, `int32`, `int64`, `uint`, `uint8` (= `byte`), `uint16`, `uint32`, `uint64`, `uintptr`

**Float types**: `float32`, `float64` (prefer float64)

```go
// Arithmetic operators
+ - * / %       // division of ints truncates
++ --           // statements only (not expressions)

// Bitwise
& | ^ &^ << >>
```

**math package**

```go
math.Abs(-3.2)         // 3.2 (float64 only)
math.Max(a, b)         // float64; for ints use cmp.Compare or manual
math.Min(a, b)
math.Ceil(2.1)         // 3.0
math.Floor(2.9)        // 2.0
math.Pow(2, 10)        // 1024.0
math.Sqrt(16)          // 4.0
math.Inf(1)            // +Inf
math.MaxInt            // largest int for platform
math.MaxFloat64
```

**strconv** (string <-> number):

```go
s := strconv.Itoa(42)                     // int -> string: "42"
n, err := strconv.Atoi("42")             // string -> int
f, err := strconv.ParseFloat("3.14", 64) // string -> float64
s = strconv.FormatFloat(3.14, 'f', 2, 64) // float -> string: "3.14"
n, err = strconv.ParseInt("FF", 16, 64)  // hex string -> int64: 255
```

---

## Strings

> Immutable UTF-8 byte sequences. `len(s)` returns bytes, not runes. Use `[]rune` for character-level work.

**strings package functions**

| Function | Purpose | Example |
|----------|---------|---------|
| `Contains(s, sub)` | Substring check | `strings.Contains("hello", "ell")` -> true |
| `HasPrefix(s, pre)` | Starts with | `strings.HasPrefix("hello", "he")` -> true |
| `HasSuffix(s, suf)` | Ends with | `strings.HasSuffix("file.go", ".go")` -> true |
| `Split(s, sep)` | Split into slice | `strings.Split("a,b,c", ",")` -> [a b c] |
| `Fields(s)` | Split on whitespace | `strings.Fields("  a  b  ")` -> [a b] |
| `Join(sl, sep)` | Join slice | `strings.Join(sl, ", ")` |
| `Replace(s, old, new, n)` | Replace first n | `strings.Replace(s, "a", "b", 1)` |
| `ReplaceAll(s, old, new)` | Replace all | `strings.ReplaceAll(s, "a", "b")` |
| `TrimSpace(s)` | Trim leading/trailing ws | `strings.TrimSpace("  hi  ")` -> "hi" |
| `ToLower(s)` | Lowercase | `strings.ToLower("GO")` -> "go" |
| `ToUpper(s)` | Uppercase | `strings.ToUpper("go")` -> "GO" |
| `Repeat(s, n)` | Repeat n times | `strings.Repeat("ab", 3)` -> "ababab" |
| `Count(s, sub)` | Count occurrences | `strings.Count("aaa", "a")` -> 3 |
| `Index(s, sub)` | First occurrence (-1 if not found) | `strings.Index("hello", "ll")` -> 2 |

**strings.Builder** (efficient string concatenation):

```go
var b strings.Builder
b.WriteString("hello")
b.WriteByte(' ')
b.WriteRune('☃')  // snowman
result := b.String()
```

**[]byte vs []rune**

- `[]byte` -- for I/O, network, file content, ASCII manipulation
- `[]rune` -- for character-level Unicode manipulation (indexing, reversing, counting chars)

```go
s := "café"          // "cafe" + combining accent = "café" visually
len(s)                     // 6 (bytes)
len([]rune(s))             // 5 (runes)
```

**fmt.Sprintf formatting**

```go
fmt.Sprintf("name=%s age=%d score=%.2f", name, age, score)
fmt.Sprintf("hex=%x ptr=%p", 255, &x)
fmt.Errorf("open %s: %w", path, err)  // %w wraps error
```

**Format verbs**

| Verb | Description | Example output |
|------|-------------|---------------|
| `%v` | Default format | `{Alice 30}` |
| `%+v` | Struct with field names | `{Name:Alice Age:30}` |
| `%#v` | Go syntax representation | `main.Person{Name:"Alice", Age:30}` |
| `%T` | Type name | `main.Person` |
| `%d` | Integer (decimal) | `42` |
| `%b` | Integer (binary) | `101010` |
| `%x` | Integer/bytes (hex) | `2a` |
| `%f` | Float (default precision) | `3.141593` |
| `%e` | Float (scientific) | `3.141593e+00` |
| `%s` | String | `hello` |
| `%q` | Quoted string | `"hello"` |
| `%p` | Pointer | `0xc0000b4008` |
| `%w` | Wrap error (Errorf only) | -- |

---

## Slices

> Dynamic-length sequences backed by arrays. The workhorse data structure in Go.

```go
// Creating
s := []int{1, 2, 3}              // literal
s := make([]int, 5)              // len=5, cap=5, zeroed
s := make([]int, 0, 100)         // len=0, cap=100
var s []int                      // nil slice (len=0, cap=0, == nil)

// Accessing
v := s[2]                        // index
sub := s[1:4]                    // slice [low:high) — shares backing array
sub := s[1:4:4]                  // [low:high:max] — limits cap to max-low

// Appending
s = append(s, 4)                 // single element
s = append(s, 5, 6, 7)          // multiple elements
s = append(s, other...)          // append another slice
```

**slices package** (standard library since 1.21)

| Function | Purpose |
|----------|---------|
| `Sort(s)` | Sort cmp.Ordered types ascending |
| `SortFunc(s, cmp)` | Sort with custom comparator |
| `SortStableFunc(s, cmp)` | Stable sort with comparator |
| `BinarySearch(s, target)` | Returns index, found bool (sorted input) |
| `BinarySearchFunc(s, target, cmp)` | Binary search with comparator |
| `Contains(s, v)` | Linear search for value |
| `ContainsFunc(s, f)` | Linear search with predicate |
| `Index(s, v)` | First index of value (-1 if absent) |
| `IndexFunc(s, f)` | First index matching predicate |
| `Clone(s)` | Shallow copy |
| `Reverse(s)` | Reverse in-place |
| `Compact(s)` | Remove consecutive duplicates |
| `Delete(s, i, j)` | Remove elements [i:j) |
| `Insert(s, i, vals...)` | Insert at index i |
| `Replace(s, i, j, vals...)` | Replace [i:j) with vals |
| `Grow(s, n)` | Ensure capacity for n more elements |

```go
// Multi-key sort with cmp.Or
slices.SortFunc(people, func(a, b Person) int {
    return cmp.Or(cmp.Compare(a.Age, b.Age), cmp.Compare(a.Name, b.Name))
})
```

**Copy**

```go
dst := make([]int, len(src))
copy(dst, src)                   // built-in copy
dst := slices.Clone(src)         // equivalent
```

**Slice tricks**

```go
// Remove at index i (order preserved)
s = slices.Delete(s, i, i+1)
// or manually:
s = append(s[:i], s[i+1:]...)

// Insert v at index i
s = slices.Insert(s, i, v)

// Filter in-place (no allocation)
n := 0
for _, v := range s {
    if keep(v) { s[n] = v; n++ }
}
s = s[:n]

// Remove consecutive duplicates
slices.Sort(s)
s = slices.Compact(s)
```

**Length vs capacity**: `len(s)` = number of elements, `cap(s)` = size of backing array from start of slice. Append doubles capacity when full.

---

## Maps

> Unordered key-value hash tables. Keys must be comparable (no slices, maps, or funcs).

```go
// Creating
m := map[string]int{"a": 1, "b": 2}   // literal
m := make(map[string]int)               // empty map (not nil)
m := make(map[string]int, 100)          // with capacity hint

// CRUD
m["key"] = 42            // create/update
v := m["key"]            // read (zero value if missing)
delete(m, "key")         // delete (no-op if missing)
clear(m)                 // remove all entries (1.21+)

// Comma-ok idiom
v, ok := m["key"]
if !ok { /* key not present */ }
```

**maps package** (standard library)

| Function | Purpose |
|----------|---------|
| `Keys(m)` | Returns iter.Seq[K] of keys |
| `Values(m)` | Returns iter.Seq[V] of values |
| `Clone(m)` | Shallow copy |
| `Copy(dst, src)` | Copy all k/v from src into dst |
| `DeleteFunc(m, f)` | Delete entries where f returns true |
| `Equal(m1, m2)` | Deep equality check |

```go
// Materialize keys to a slice
keys := slices.Collect(maps.Keys(m))

// map as set
seen := make(map[string]struct{})
seen["x"] = struct{}{}
_, exists := seen["x"]
```

**Iteration order is random** -- never rely on map ordering. Sort keys if deterministic order needed.

---

## Structs

> Composite types that group fields. Methods define behavior.

```go
// Defining
type Person struct {
    Name string
    Age  int
}

// Initializing
p := Person{Name: "Alice", Age: 30}   // named fields (preferred)
p := Person{"Alice", 30}               // positional (fragile, avoid in public API)
p := new(Person)                        // returns *Person, zero-valued

// Methods — value receiver vs pointer receiver
func (p Person) String() string { return p.Name }        // can't mutate p
func (p *Person) SetName(n string) { p.Name = n }       // can mutate p

// Embedding (composition, not inheritance)
type Employee struct {
    Person               // promotes Person's fields and methods
    Company string
}
e := Employee{Person: Person{Name: "Bob", Age: 25}, Company: "Acme"}
fmt.Println(e.Name)     // promoted field access

// Tags — metadata for json, db, validation
type User struct {
    ID    int    `json:"id" db:"user_id"`
    Email string `json:"email,omitempty"`
}

// Anonymous structs — useful for one-off test data
point := struct{ X, Y int }{10, 20}
```

---

## Interfaces

> Define behavior contracts. Satisfied implicitly -- no `implements` keyword.

```go
// Defining
type Writer interface {
    Write(p []byte) (n int, err error)
}

// A type satisfies an interface by implementing all its methods
type MyWriter struct{}
func (w MyWriter) Write(p []byte) (int, error) { return len(p), nil }
// MyWriter now satisfies io.Writer automatically
```

**Common interfaces**

| Interface | Methods | Package |
|-----------|---------|---------|
| `error` | `Error() string` | builtin |
| `fmt.Stringer` | `String() string` | fmt |
| `io.Reader` | `Read([]byte) (int, error)` | io |
| `io.Writer` | `Write([]byte) (int, error)` | io |
| `io.Closer` | `Close() error` | io |
| `io.ReadWriter` | Read + Write | io |
| `sort.Interface` | `Len, Less, Swap` | sort |
| `json.Marshaler` | `MarshalJSON() ([]byte, error)` | encoding/json |
| `json.Unmarshaler` | `UnmarshalJSON([]byte) error` | encoding/json |
| `http.Handler` | `ServeHTTP(ResponseWriter, *Request)` | net/http |

```go
// Empty interface — accepts any value
var x any   // same as interface{}

// Type assertion — extract concrete type
r, ok := w.(io.Reader)
if !ok { /* w doesn't implement io.Reader */ }

// Type switch — branch on concrete type
switch v := x.(type) {
case int:       fmt.Println(v + 1)
case string:    fmt.Println(len(v))
case error:     fmt.Println(v.Error())
default:        fmt.Printf("unexpected: %T\n", v)
}
```

---

## Control Flow

> Branching, looping, and deferring cleanup.

```go
// if/else with init statement
if err := doWork(); err != nil {
    return err
}

// for — three forms
for i := 0; i < n; i++ { }       // classic
for n > 0 { n-- }                 // while-form
for { break }                     // infinite

// range patterns
for i, v := range slice { }       // index + value
for k, v := range aMap { }        // key + value
for i, ch := range "hello" { }    // index (byte pos) + rune
for v := range channel { }        // receive until closed
for i := range 10 { }             // 0..9 (Go 1.22+)

// switch — no fallthrough by default
switch status {
case 200: ok()
case 404: notFound()
case 500, 502, 503: serverErr()
default: unknown()
}

// Expression switch (no tag)
switch {
case age < 13:  category = "child"
case age < 20:  category = "teen"
default:        category = "adult"
}

// defer — runs on function return, LIFO order
f, _ := os.Open(path)
defer f.Close()          // guaranteed cleanup

// Labeled break/continue
outer:
for i := range rows {
    for j := range cols {
        if rows[i][j] == target { break outer }
    }
}
```

---

## Functions

> First-class values. Multiple returns, variadic args, closures.

```go
// Multiple return values
func divide(a, b float64) (float64, error) {
    if b == 0 { return 0, errors.New("division by zero") }
    return a / b, nil
}

// Named returns (useful for documenting, use sparingly)
func split(sum int) (x, y int) {
    x = sum * 4 / 9
    y = sum - x
    return  // naked return
}

// Variadic
func sum(nums ...int) int {
    total := 0
    for _, n := range nums { total += n }
    return total
}
sum(1, 2, 3)
sum(slice...)           // spread a slice

// First-class functions / closures
apply := func(f func(int) int, x int) int { return f(x) }
double := func(n int) int { return n * 2 }
apply(double, 5)        // 10

// Closure capturing state
func counter() func() int {
    n := 0
    return func() int { n++; return n }
}

// defer, panic, recover
func safeDiv(a, b int) (result int, err error) {
    defer func() {
        if r := recover(); r != nil {
            err = fmt.Errorf("panic: %v", r)
        }
    }()
    return a / b, nil   // panics if b == 0
}
```

---

## Error Handling

> Errors are values. Return (T, error), check immediately, wrap for context.

```go
// Basic pattern
result, err := doWork()
if err != nil {
    return fmt.Errorf("doWork failed: %w", err)  // wrap with context
}

// Sentinel errors
var ErrNotFound = errors.New("not found")
var ErrTimeout  = errors.New("timeout")

// Custom error type
type ValidationError struct {
    Field string
    Msg   string
}
func (e *ValidationError) Error() string {
    return fmt.Sprintf("%s: %s", e.Field, e.Msg)
}
```

**errors package**

| Function | Purpose |
|----------|---------|
| `New(text)` | Create simple error |
| `Is(err, target)` | Check if err (or any wrapped) matches target |
| `As(err, &target)` | Find first error in chain assignable to target type |
| `AsType[T](err)` | Generic As -- returns (T, bool) (Go 1.26) |
| `Join(errs...)` | Combine multiple errors into one |
| `Unwrap(err)` | Get the next error in the chain |

```go
// errors.Is — matches sentinel values through wrapping chain
if errors.Is(err, ErrNotFound) { return 404 }

// errors.As — extract typed error
var ve *ValidationError
if errors.As(err, &ve) { fmt.Println(ve.Field) }

// errors.AsType (Go 1.26) — generic alternative, no pointer variable needed
if ve, ok := errors.AsType[*ValidationError](err); ok {
    fmt.Println(ve.Field)
}

// Wrapping multiple errors
err := errors.Join(err1, err2, err3)
// errors.Is checks each wrapped error
```

---

## Generics

> Write type-safe code that works across multiple types (Go 1.18+).

```go
// Generic function
func Filter[T any](s []T, pred func(T) bool) []T {
    var out []T
    for _, v := range s {
        if pred(v) { out = append(out, v) }
    }
    return out
}

// Generic type
type Set[T comparable] map[T]struct{}
func (s Set[T]) Add(v T)       { s[v] = struct{}{} }
func (s Set[T]) Has(v T) bool  { _, ok := s[v]; return ok }
func (s Set[T]) Del(v T)       { delete(s, v) }

// Constraints
// any           — no restrictions
// comparable    — supports == and != (map keys, etc.)
// cmp.Ordered   — supports < > <= >= (numbers + strings)

// Underlying type constraint (~)
type Integer interface { ~int | ~int8 | ~int16 | ~int32 | ~int64 }
type MyInt int              // MyInt satisfies Integer due to ~int

// cmp.Compare — returns -1, 0, or +1
cmp.Compare(a, b)

// cmp.Or — first non-zero result (for multi-key sorting)
slices.SortFunc(items, func(a, b Item) int {
    return cmp.Or(
        cmp.Compare(a.Category, b.Category),
        cmp.Compare(a.Price, b.Price),
    )
})
```

---

## Concurrency

> Goroutines are lightweight threads. Channels synchronize and communicate.

```go
// Goroutines
go func() { result <- compute() }()

// Channels
ch := make(chan int)        // unbuffered (synchronous)
ch := make(chan int, 10)    // buffered (async up to 10)
ch <- value                 // send (blocks if full / no receiver)
v := <-ch                   // receive (blocks if empty / no sender)
close(ch)                   // close — receivers get zero values
for v := range ch { }       // receive until closed

// Select — multiplex channel operations
select {
case msg := <-inbox:    handle(msg)
case <-ctx.Done():      return ctx.Err()
case outbox <- result:  // sent
default:                // non-blocking: execute immediately if no case ready
}
```

**sync package**

| Type | Purpose |
|------|---------|
| `Mutex` | Exclusive lock (Lock / Unlock) |
| `RWMutex` | Multiple readers OR one writer (RLock/RUnlock, Lock/Unlock) |
| `WaitGroup` | Wait for a group of goroutines to finish |
| `Once` | Run a function exactly once (thread-safe singleton) |
| `Map` | Concurrent-safe map (avoid unless high contention) |
| `Pool` | Reusable object pool (reduce GC pressure) |

```go
// sync.WaitGroup
var wg sync.WaitGroup
wg.Add(1)
go func() { defer wg.Done(); work() }()
wg.Wait()

// wg.Go (Go 1.25+) — spawns goroutine with automatic Add/Done
var wg sync.WaitGroup
wg.Go(func() { work() })
wg.Wait()

// sync.Mutex
var mu sync.Mutex
mu.Lock()
defer mu.Unlock()
// ... critical section ...

// sync.Once
var once sync.Once
once.Do(func() { expensiveInit() })
```

**context** — propagate cancellation, deadlines, and request-scoped values.

```go
ctx, cancel := context.WithCancel(context.Background())
defer cancel()

ctx, cancel := context.WithTimeout(parent, 5*time.Second)
defer cancel()

ctx = context.WithValue(ctx, key, value)
val := ctx.Value(key)

// Check cancellation cause (Go 1.20+)
cause := context.Cause(ctx)
```

**errgroup** (golang.org/x/sync/errgroup) — goroutine group with error propagation:

```go
g, ctx := errgroup.WithContext(ctx)
g.Go(func() error { return fetchA(ctx) })
g.Go(func() error { return fetchB(ctx) })
if err := g.Wait(); err != nil { /* first non-nil error */ }
```

---

## Iteration (1.22+)

> Modern Go supports range over integers and custom iterator functions.

```go
// Range over integers (Go 1.22+)
for i := range 10 { fmt.Println(i) }   // 0..9

// Range-over-func iterators (Go 1.23+)
// iter.Seq[V] — single-value iterator
// iter.Seq2[K, V] — two-value iterator (like index + value)

// Custom iterator — yields values until consumer stops
func Words(s string) iter.Seq[string] {
    return func(yield func(string) bool) {
        for _, w := range strings.Fields(s) {
            if !yield(w) { return }
        }
    }
}
for w := range Words("hello world") { fmt.Println(w) }

// Two-value iterator
func Enumerate[T any](s []T) iter.Seq2[int, T] {
    return func(yield func(int, T) bool) {
        for i, v := range s {
            if !yield(i, v) { return }
        }
    }
}

// Pull-based iterators — convert push (yield) to pull (next/stop)
next, stop := iter.Pull(Words("a b c"))
defer stop()
w1, ok := next()   // "a", true
w2, ok := next()   // "b", true

// iter.Pull2 — same for two-value iterators
next2, stop2 := iter.Pull2(Enumerate(items))
defer stop2()
i, v, ok := next2()

// Collecting into a slice
words := slices.Collect(Words("hello world"))
```

---

## Testing

> Tests live in `_test.go` files. Run with `go test ./...`.

```go
// Basic test
func TestAdd(t *testing.T) {
    got := Add(2, 3)
    if got != 5 { t.Errorf("Add(2,3) = %d, want 5", got) }
}

// Table-driven tests
func TestFib(t *testing.T) {
    tests := []struct {
        name string
        n, want int
    }{
        {"zero", 0, 0},
        {"one", 1, 1},
        {"ten", 10, 55},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            assert.Equal(t, tt.want, Fib(tt.n))
        })
    }
}

// Helpers and cleanup
func tempFile(t *testing.T) string {
    t.Helper()                              // marks as helper (errors show caller)
    f, err := os.CreateTemp("", "test-*")
    require.NoError(t, err)
    t.Cleanup(func() { os.Remove(f.Name()) })  // runs after test
    return f.Name()
}

// Parallel tests
func TestSlow(t *testing.T) {
    t.Parallel()                            // run concurrently with other parallel tests
}
```

**testify/assert** (common assertions)

| Function | Purpose |
|----------|---------|
| `Equal(t, expected, actual)` | Deep equality |
| `NotEqual(t, a, b)` | Not equal |
| `NoError(t, err)` | err == nil |
| `Error(t, err)` | err != nil |
| `Len(t, obj, length)` | Length check |
| `Contains(t, haystack, needle)` | Substring/element check |
| `Empty(t, obj)` | Zero length |
| `Nil(t, obj)` | Is nil |
| `NotNil(t, obj)` | Not nil |
| `True(t, val)` | val == true |
| `False(t, val)` | val == false |

**testing/synctest** (Go 1.25+) — deterministic testing of concurrent code:

```go
synctest.Run(func() {
    ch := make(chan int)
    go func() { ch <- 42 }()
    synctest.Wait()              // wait for all goroutines to block
    assert.Equal(t, 42, <-ch)
})
```

**Benchmarks**

```go
func BenchmarkFib(b *testing.B) {
    for b.Loop() {               // Go 1.24+: replaces for i := 0; i < b.N; i++
        Fib(20)
    }
}
// Run: go test -bench=. -benchmem
```

---

## I/O & Files

> Reading, writing, and navigating the filesystem.

```go
// Read entire file
data, err := os.ReadFile("config.json")

// Write entire file
err := os.WriteFile("out.txt", []byte(content), 0644)

// Open for streaming
f, err := os.Open("data.txt")     // read-only
if err != nil { return err }
defer f.Close()

// Create/truncate for writing
f, err := os.Create("output.txt")
defer f.Close()
f.WriteString("hello\n")

// Line-by-line reading with bufio.Scanner
scanner := bufio.NewScanner(file)
for scanner.Scan() {
    line := scanner.Text()
}
if err := scanner.Err(); err != nil { /* handle */ }

// io utilities
io.Copy(dst, src)          // stream from reader to writer
data, err := io.ReadAll(r) // read everything (careful with large inputs)
```

**filepath package**

| Function | Purpose | Example |
|----------|---------|---------|
| `Join(parts...)` | OS-aware path joining | `filepath.Join("a", "b", "c.txt")` -> `a/b/c.txt` |
| `Base(path)` | Last element | `filepath.Base("/a/b/file.go")` -> `file.go` |
| `Dir(path)` | Directory portion | `filepath.Dir("/a/b/file.go")` -> `/a/b` |
| `Ext(path)` | Extension | `filepath.Ext("archive.tar.gz")` -> `.gz` |
| `Glob(pattern)` | Match files | `filepath.Glob("*.go")` |
| `Abs(path)` | Absolute path | `filepath.Abs("./rel")` |
| `Rel(base, target)` | Relative path | `filepath.Rel("/a", "/a/b/c")` -> `b/c` |
| `Walk/WalkDir` | Recursive traversal | see os.WalkDir |

---

## JSON

> Encoding/decoding between Go structs and JSON.

```go
// Marshal (struct -> JSON bytes)
data, err := json.Marshal(user)

// Unmarshal (JSON bytes -> struct)
var user User
err := json.Unmarshal(data, &user)

// Struct tags control JSON field names and behavior
type User struct {
    ID        int    `json:"id"`
    FirstName string `json:"first_name"`
    Email     string `json:"email,omitempty"`  // omit if zero value
    Password  string `json:"-"`                // always omit
}

// Streaming with encoder/decoder (for http bodies, files)
json.NewEncoder(w).Encode(response)           // write JSON to io.Writer
json.NewDecoder(r.Body).Decode(&request)      // read JSON from io.Reader

// Dynamic JSON (unknown structure)
var result map[string]any
json.Unmarshal(data, &result)
name := result["name"].(string)               // type assert fields

// Pretty print
data, _ := json.MarshalIndent(obj, "", "  ")
```

---

## Common Patterns

> Idiomatic Go recipes you will reach for repeatedly.

```go
// defer for cleanup
f, err := os.Open(path)
if err != nil { return err }
defer f.Close()

mu.Lock()
defer mu.Unlock()

ctx, cancel := context.WithTimeout(parent, 5*time.Second)
defer cancel()

// Comma-ok idiom
val, ok := m[key]           // map lookup
conn, ok := x.(net.Conn)   // type assertion
v, ok := <-ch              // channel receive (ok=false if closed & empty)

// Guard clause / early return
func process(r *Request) error {
    if r == nil { return errors.New("nil request") }
    if r.URL == "" { return errors.New("empty URL") }
    // happy path continues unindented...
}

// Functional options (extensible constructors)
type Option func(*Server)
func WithPort(p int) Option   { return func(s *Server) { s.port = p } }
func WithTLS(cert string) Option { return func(s *Server) { s.cert = cert } }

func NewServer(opts ...Option) *Server {
    s := &Server{port: 8080}
    for _, o := range opts { o(s) }
    return s
}
srv := NewServer(WithPort(9090), WithTLS("cert.pem"))

// Builder pattern with method chaining
type Query struct { parts []string }
func (q *Query) Where(c string) *Query  { q.parts = append(q.parts, c); return q }
func (q *Query) Limit(n int) *Query     { q.parts = append(q.parts, fmt.Sprintf("LIMIT %d", n)); return q }
func (q *Query) Build() string          { return strings.Join(q.parts, " ") }

// Interface-based mocking (for tests)
type Store interface {
    Get(id string) (Item, error)
    Put(item Item) error
}
type mockStore struct { items map[string]Item }
func (m *mockStore) Get(id string) (Item, error) { /* ... */ }
```

---

## Useful Standard Library

> Quick reference for the most-used packages.

| Package | Purpose |
|---------|---------|
| `fmt` | Formatted I/O (Printf, Sprintf, Errorf) |
| `strings` | String manipulation (Split, Join, Contains, Builder) |
| `strconv` | String/number conversions (Atoi, Itoa, Parse*) |
| `slices` | Generic slice operations (Sort, Contains, Filter) |
| `maps` | Generic map operations (Keys, Values, Clone) |
| `cmp` | Comparison helpers (Compare, Or, Ordered constraint) |
| `iter` | Iterator types (Seq, Seq2, Pull, Pull2) |
| `errors` | Error wrapping and inspection (Is, As, Join) |
| `io` | Reader/Writer interfaces and utilities (Copy, ReadAll) |
| `os` | OS interaction (files, env, args, signals) |
| `bufio` | Buffered I/O (Scanner for line reading) |
| `filepath` | OS-portable path manipulation (Join, Base, Walk) |
| `encoding/json` | JSON marshal/unmarshal |
| `net/http` | HTTP client and server |
| `context` | Cancellation, deadlines, request-scoped values |
| `sync` | Mutex, WaitGroup, Once, Pool |
| `time` | Duration, Timer, Ticker, time.Now, time.Since |
| `regexp` | Regular expressions (Compile, FindString, Match) |
| `math` | Math functions (Abs, Max, Pow, Sqrt) |
| `math/rand/v2` | Random numbers (N, IntN, Float64, Shuffle) |
| `log/slog` | Structured logging (Info, Warn, Error, With) |
| `container/heap` | Priority queue interface |
| `container/list` | Doubly-linked list |
| `crypto/rand` | Cryptographically secure random bytes |
| `testing` | Test framework (T, B, F for fuzzing) |
