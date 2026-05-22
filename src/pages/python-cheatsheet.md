---
layout: ../layouts/GistLayout.astro
tags: [python, guide]
---

# Python Cheat Sheet (Complete Reference)

- [Variables & Types](#variables--types)
- [Numbers](#numbers)
- [Strings](#strings)
- [Lists](#lists)
- [Tuples](#tuples)
- [Dictionaries](#dictionaries)
- [Sets](#sets)
- [Control Flow](#control-flow)
- [Functions](#functions)
- [Comprehensions & Generators](#comprehensions--generators)
- [Classes](#classes)
- [Error Handling](#error-handling)
- [File I/O](#file-io)
- [Collections Module](#collections-module)
- [itertools](#itertools)
- [functools](#functools)
- [Sorting & Searching](#sorting--searching)
- [Regular Expressions](#regular-expressions)
- [Async](#async)
- [Type Hints](#type-hints)
- [Useful Built-ins](#useful-built-ins)

## Variables & Types

Use for assignments, type checking, and understanding Python's dynamic type system.

```python
# Type checking
isinstance(x, int)              # preferred — respects inheritance
isinstance(x, (int, float))     # check against multiple types
type(x) is int                  # exact type match (no subclass)

# Truthiness — these are all falsy:
# False, None, 0, 0.0, 0j, "", [], (), {}, set(), frozenset(), range(0)
# Everything else is truthy (including non-empty containers, objects)

# Ternary expression
result = "yes" if condition else "no"

# Multiple assignment
a, b, c = 1, 2, 3
x = y = z = 0                   # all point to same object

# Swap
a, b = b, a
```

## Numbers

Use for arithmetic, rounding, and mathematical operations.

```python
# Integer operations
7 // 2        # 3   (floor division — rounds toward negative infinity)
7 % 2         # 1   (modulo)
2 ** 10       # 1024 (exponentiation)
divmod(7, 2)  # (3, 1) — quotient and remainder together

# Useful built-ins
abs(-5)                # 5
round(3.456, 2)        # 3.46  (banker's rounding: round(2.5) == 2)
min(3, 1, 4)           # 1
max(3, 1, 4)           # 4
sum([1, 2, 3], start=0)  # 6

# Math module
import math
math.ceil(3.2)         # 4
math.floor(3.9)        # 3
math.inf               # positive infinity (useful as initial max)
math.isclose(0.1 + 0.2, 0.3)  # True (handles float imprecision)
math.gcd(12, 8)        # 4
math.log(100, 10)      # 2.0
math.sqrt(16)          # 4.0
```

## Strings

Use for text manipulation, formatting, and searching.

### Common String Methods

| Method | Example | Result |
|--------|---------|--------|
| `split(sep)` | `"a,b,c".split(",")` | `['a', 'b', 'c']` |
| `join(iter)` | `",".join(["a","b"])` | `"a,b"` |
| `strip()` | `"  hi  ".strip()` | `"hi"` |
| `replace(old, new)` | `"hello".replace("l","L")` | `"heLLo"` |
| `find(sub)` | `"hello".find("ll")` | `2` (-1 if not found) |
| `count(sub)` | `"banana".count("a")` | `3` |
| `startswith(s)` | `"readme.md".startswith("read")` | `True` |
| `endswith(s)` | `"readme.md".endswith((".md",".txt"))` | `True` (tuple OK) |
| `upper()` | `"hi".upper()` | `"HI"` |
| `lower()` | `"Hi".lower()` | `"hi"` |
| `title()` | `"hello world".title()` | `"Hello World"` |
| `isdigit()` | `"123".isdigit()` | `True` |
| `isalpha()` | `"abc".isalpha()` | `True` |
| `isalnum()` | `"abc123".isalnum()` | `True` |

### f-string Format Specifiers

| Spec | Example | Result | Use For |
|------|---------|--------|---------|
| `<n` | `f"{'hi':<10}"` | `"hi        "` | Left-align |
| `>n` | `f"{'hi':>10}"` | `"        hi"` | Right-align |
| `^n` | `f"{'hi':^10}"` | `"    hi    "` | Center |
| `.nf` | `f"{3.14159:.2f}"` | `"3.14"` | Decimal places |
| `,` | `f"{1000000:,}"` | `"1,000,000"` | Thousands sep |
| `_` | `f"{1000000:_}"` | `"1_000_000"` | Underscore sep |
| `#x` | `f"{255:#x}"` | `"0xff"` | Hex with prefix |
| `#b` | `f"{10:#b}"` | `"0b1010"` | Binary with prefix |
| `%` | `f"{0.75:%}"` | `"75.000000%"` | Percentage |
| `e` | `f"{12345.6:e}"` | `"1.234560e+04"` | Scientific |

```python
# Raw strings — backslashes not treated as escapes
path = r"C:\Users\name\docs"

# Multiline strings
msg = """Line one
Line two
Line three"""

# Multiline f-string
name = "world"
msg = (
    f"Hello {name}, "
    f"today is {date}"
)

# String slicing
s = "Hello, World!"
s[::-1]       # '!dlroW ,olleH' — reverse
s[::2]        # 'Hlo ol!' — every 2nd char
s[7:]         # 'World!'
s[-6:-1]      # 'World'
```

## Lists

Use for ordered, mutable sequences with fast index access and iteration.

```python
# Creating
nums = [1, 2, 3, 4, 5]
zeros = [0] * 10              # [0, 0, 0, ..., 0]
from_range = list(range(5))   # [0, 1, 2, 3, 4]

# Accessing & slicing
nums[0]       # 1 (first)
nums[-1]      # 5 (last)
nums[1:3]     # [2, 3] (slice — excludes end)
nums[::2]     # [1, 3, 5] (step)
nums[::-1]    # [5, 4, 3, 2, 1] (reverse)
```

### Mutating Methods (modify in-place, return None)

| Method | Effect |
|--------|--------|
| `append(x)` | Add x to end |
| `extend(iter)` | Append all items from iterable |
| `insert(i, x)` | Insert x before index i |
| `pop(i=-1)` | Remove and return item at index (default last) |
| `remove(x)` | Remove first occurrence of x (raises ValueError if absent) |
| `clear()` | Remove all items |
| `sort(key=, reverse=)` | Sort in-place |
| `reverse()` | Reverse in-place |

### Non-mutating Operations (return new value)

| Function | Result |
|----------|--------|
| `sorted(lst, key=, reverse=)` | New sorted list |
| `reversed(lst)` | Reverse iterator |
| `len(lst)` | Number of items |
| `min(lst)` | Smallest item |
| `max(lst)` | Largest item |
| `sum(lst)` | Sum of items |
| `any(lst)` | True if any truthy |
| `all(lst)` | True if all truthy |

```python
# List comprehension with condition
evens = [x for x in range(20) if x % 2 == 0]

# Nested comprehension (flatten)
flat = [x for row in matrix for x in row]

# Unpacking
first, *middle, last = [1, 2, 3, 4, 5]
merged = [*list_a, *list_b]

# Copy: shallow vs deep
import copy
shallow = nums[:]             # or list(nums) or nums.copy()
deep = copy.deepcopy(nested)  # recursively copies nested objects
```

## Tuples

Use for immutable sequences: dict keys, function return values, fixed data.

```python
# Creating
t = (1, 2, 3)
single = (42,)                # trailing comma required for single-element
t = tuple([1, 2, 3])         # from iterable

# Immutability — can't assign to t[0]
# But mutable contents CAN change: ([1,2],)[0].append(3) is valid

# Unpacking
x, y, z = (1, 2, 3)
first, *rest = (1, 2, 3, 4)

# namedtuple — lightweight class alternative
from collections import namedtuple
Point = namedtuple("Point", ["x", "y"])
p = Point(3, 4)
p.x               # 3
p._asdict()        # {'x': 3, 'y': 4}
p._replace(x=10)   # Point(x=10, y=4) — returns new tuple

# When to use tuples:
# - As dict keys (immutable, hashable)
# - Multiple return values from functions
# - Fixed-structure data (coordinates, RGB values)
# - Slightly faster than lists for iteration
```

## Dictionaries

Use for key-value mappings with O(1) lookup.

```python
# Creating
d = {"name": "Alice", "age": 30}
d = dict(name="Alice", age=30)
d = dict.fromkeys(["a", "b", "c"], 0)  # {'a': 0, 'b': 0, 'c': 0}

# Accessing
d["name"]                  # 'Alice' — raises KeyError if missing
d.get("name", "unknown")   # 'Alice' — returns default if missing
```

### Dict Methods

| Method | Description |
|--------|-------------|
| `d.keys()` | View of keys |
| `d.values()` | View of values |
| `d.items()` | View of (key, value) pairs |
| `d.get(k, default)` | Get value or default (no KeyError) |
| `d.setdefault(k, v)` | Get value; if missing, insert v and return it |
| `d.pop(k, default)` | Remove and return value (or default) |
| `d.update(other)` | Merge other dict into d (in-place) |
| `d \| other` | Merge — new dict (3.9+) |
| `d \|= other` | Merge — in-place update (3.9+) |

```python
# Dict comprehension
squared = {x: x**2 for x in range(5)}

# Merge with | (3.9+)
merged = defaults | overrides           # new dict
config |= {"debug": True}              # in-place

# setdefault — get or insert
graph.setdefault(node, []).append(edge)

# defaultdict — auto-creates missing keys
from collections import defaultdict
graph = defaultdict(list)
graph["a"].append("b")          # no KeyError
freq = defaultdict(int)
freq["x"] += 1                  # starts at 0

# Counter — specialized dict for counting
from collections import Counter
c = Counter("abracadabra")
c.most_common(2)                # [('a', 5), ('b', 2)]
Counter("aab") & Counter("abc") # intersection: Counter({'a': 1, 'b': 1})

# Nested dicts
nested = {"users": {"alice": {"age": 30}}}
nested["users"]["alice"]["age"]   # 30
# Safe nested access:
nested.get("users", {}).get("alice", {}).get("age", None)
```

## Sets

Use for unique collections, membership testing, and mathematical set operations.

```python
# Creating
s = {1, 2, 3}
s = set([1, 2, 2, 3])    # {1, 2, 3} — duplicates removed
s = set()                  # empty set (NOT {} — that's an empty dict)
s = {x**2 for x in range(5)}  # set comprehension: {0, 1, 4, 9, 16}
```

### Set Operations (Operators)

| Operator | Method | Result |
|----------|--------|--------|
| `a \| b` | `a.union(b)` | All elements from both |
| `a & b` | `a.intersection(b)` | Elements in both |
| `a - b` | `a.difference(b)` | Elements in a but not b |
| `a ^ b` | `a.symmetric_difference(b)` | Elements in one but not both |

### Set Methods

| Method | Description |
|--------|-------------|
| `add(x)` | Add element |
| `discard(x)` | Remove x (no error if absent) |
| `remove(x)` | Remove x (raises KeyError if absent) |
| `issubset(other)` | All elements of self in other? |
| `issuperset(other)` | All elements of other in self? |
| `isdisjoint(other)` | No elements in common? |

```python
# Frozenset — immutable set, can be used as dict key or in other sets
fs = frozenset([1, 2, 3])
```

## Control Flow

Use for branching, looping, and structural pattern matching.

```python
# if/elif/else
if x > 0:
    print("positive")
elif x == 0:
    print("zero")
else:
    print("negative")

# for loop
for i in range(5):              # 0, 1, 2, 3, 4
    pass
for i, val in enumerate(lst):   # index + value
    pass
for a, b in zip(list1, list2):  # parallel iteration
    pass
for x in reversed(lst):         # iterate backward
    pass

# while loop
while condition:
    if found:
        break
    if skip:
        continue
else:
    # runs only if loop completed without break
    print("no break occurred")

# match/case (3.10+) — structural pattern matching
match command:
    case "quit":
        sys.exit()
    case "hello":
        print("Hi!")
    case _:
        print("Unknown")

# With guards
match point:
    case (x, y) if x == y:
        print(f"On diagonal: {x}")
    case (x, y):
        print(f"Point: {x}, {y}")

# Structural matching
match data:
    case [first, *rest]:                        # sequence
        print(f"List starting with {first}")
    case {"action": action, "payload": p}:     # mapping
        handle(action, p)
    case Point(x=0, y=y):                      # class pattern
        print(f"On y-axis at {y}")
```

## Functions

Use for reusable logic, closures, and callable abstractions.

```python
# Basic definition with return
def add(a: int, b: int) -> int:
    """Add two numbers and return the result."""
    return a + b

# Return multiple values (tuple unpacking)
def min_max(lst):
    return min(lst), max(lst)

lo, hi = min_max([3, 1, 4, 1, 5])

# *args and **kwargs
def func(*args, **kwargs):
    # args is a tuple of positional args
    # kwargs is a dict of keyword args
    pass

# Keyword-only arguments (after *)
def connect(host, port, *, timeout=30, retries=3):
    pass  # timeout and retries MUST be passed by name

# Default arguments — MUTABLE DEFAULT TRAP!
def bad(lst=[]):       # WRONG — shared across calls
    lst.append(1)
    return lst

def good(lst=None):    # CORRECT — new list each call
    if lst is None:
        lst = []
    lst.append(1)
    return lst

# Lambda — anonymous single-expression function
square = lambda x: x ** 2
sorted(pairs, key=lambda p: p[1])

# Type hints on signatures
from collections.abc import Callable
def retry(fn: Callable[[], bool], attempts: int = 3) -> bool:
    ...

# Docstrings
def calculate(x: float, y: float) -> float:
    """Calculate the weighted result.

    Args:
        x: The base value.
        y: The multiplier.

    Returns:
        The product of x and y.
    """
    return x * y
```

## Comprehensions & Generators

Use for transforming data declaratively or processing large sequences lazily.

```python
# List comprehension
squares = [x**2 for x in range(10)]
evens = [x for x in range(20) if x % 2 == 0]

# Dict comprehension
word_len = {w: len(w) for w in words}

# Set comprehension
unique_lengths = {len(w) for w in words}

# Generator expression — lazy, memory-efficient
total = sum(x * x for x in range(1_000_000))

# Generator function with yield
def fibonacci():
    a, b = 0, 1
    while True:
        yield a
        a, b = b, a + b

fib = fibonacci()
next(fib)  # 0
next(fib)  # 1

# Walrus operator := (assignment expression)
# In while loops
while chunk := f.read(8192):
    process(chunk)

# In comprehension filters
results = [m.group() for line in lines if (m := pattern.search(line))]

# In if statements
if (n := len(data)) > 10:
    print(f"Too long: {n}")
```

## Classes

Use for encapsulating state and behavior, building abstractions.

```python
# Basic class
class Animal:
    species_count = 0             # class variable (shared)

    def __init__(self, name: str):
        self.name = name          # instance variable
        Animal.species_count += 1

    def speak(self) -> str:
        return f"{self.name} makes a sound"

# Inheritance & super()
class Dog(Animal):
    def __init__(self, name: str, breed: str):
        super().__init__(name)
        self.breed = breed

    def speak(self) -> str:
        return f"{self.name} barks"

# @property — computed attribute with getter/setter
class Circle:
    def __init__(self, radius: float):
        self._radius = radius

    @property
    def area(self) -> float:
        return 3.14159 * self._radius ** 2

    @property
    def radius(self) -> float:
        return self._radius

    @radius.setter
    def radius(self, value: float):
        if value < 0:
            raise ValueError("Radius must be non-negative")
        self._radius = value

# @classmethod and @staticmethod
class Date:
    def __init__(self, year, month, day):
        self.year, self.month, self.day = year, month, day

    @classmethod
    def from_string(cls, s: str) -> "Date":
        """Alternate constructor."""
        y, m, d = map(int, s.split("-"))
        return cls(y, m, d)

    @staticmethod
    def is_leap(year: int) -> bool:
        """Utility — no access to cls or self."""
        return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)

# @dataclass — auto-generates __init__, __repr__, __eq__, etc.
from dataclasses import dataclass, field

@dataclass(frozen=True, slots=True)
class Point:
    x: float
    y: float
    tags: list = field(default_factory=list)

    def __post_init__(self):
        # Runs after __init__; for validation or derived fields
        object.__setattr__(self, 'tags', list(self.tags))

# __slots__ — restrict attributes, save memory
class Pixel:
    __slots__ = ("r", "g", "b")
    def __init__(self, r, g, b):
        self.r, self.g, self.b = r, g, b

# Key dunder methods
class Vector:
    def __repr__(self):  return f"Vector({self.x}, {self.y})"   # unambiguous repr
    def __str__(self):   return f"({self.x}, {self.y})"         # user-friendly
    def __eq__(self, other): return (self.x, self.y) == (other.x, other.y)
    def __lt__(self, other): return abs(self) < abs(other)
    def __hash__(self):  return hash((self.x, self.y))
    def __len__(self):   return 2
    def __getitem__(self, i): return (self.x, self.y)[i]
```

## Error Handling

Use for graceful failure recovery and signaling exceptional conditions.

```python
# try/except/else/finally
try:
    result = risky_operation()
except (ValueError, KeyError) as e:
    handle_error(e)
else:
    use(result)       # runs ONLY if no exception was raised
finally:
    cleanup()         # ALWAYS runs (even after return/break)

# Catching multiple exceptions separately
try:
    parse(data)
except ValueError:
    print("Bad value")
except KeyError as e:
    print(f"Missing key: {e}")

# raise and raise from (exception chaining)
try:
    connect()
except ConnectionError as e:
    raise RuntimeError("Service unavailable") from e

# Custom exception classes
class ValidationError(Exception):
    def __init__(self, field: str, message: str):
        super().__init__(f"{field}: {message}")
        self.field = field
```

### Common Exception Types

| Exception | When Raised |
|-----------|-------------|
| `ValueError` | Right type, wrong value (`int("abc")`) |
| `TypeError` | Wrong type (`len(42)`) |
| `KeyError` | Missing dict key (`d["nope"]`) |
| `IndexError` | List index out of range (`lst[99]`) |
| `AttributeError` | Missing attribute (`obj.nope`) |
| `FileNotFoundError` | File doesn't exist (`open("nope.txt")`) |
| `StopIteration` | Iterator exhausted (`next()` on empty) |
| `RuntimeError` | Generic runtime problem |
| `ZeroDivisionError` | Division by zero |

## File I/O

Use for reading/writing files and working with the filesystem.

```python
from pathlib import Path

# pathlib (preferred — cross-platform, expressive)
p = Path("data/output.txt")
p.exists()                    # True/False
p.is_file()                   # True if it's a file
p.parent                      # Path('data')
p.stem                        # 'output'
p.suffix                      # '.txt'
p.name                        # 'output.txt'
text = p.read_text()          # read entire file as string
p.write_text("hello")         # write string (creates/overwrites)
p.read_bytes()                # read as bytes
list(p.parent.glob("*.txt"))  # all .txt files in directory
list(p.parent.rglob("*.py")) # recursive glob

# open() context manager
with open("file.txt", "r") as f:
    content = f.read()           # entire file as string

with open("file.txt", "w") as f:  # write (truncates)
    f.write("hello\n")

with open("file.txt", "a") as f:  # append
    f.write("more\n")

# Reading lines
with open("file.txt") as f:
    for line in f:               # memory-efficient line iteration
        process(line.rstrip("\n"))

content.splitlines()             # split string into lines (no \n)
```

## Collections Module

Use for specialized container types beyond built-in list/dict/set.

```python
from collections import Counter, defaultdict, deque, namedtuple

# Counter — counting hashable objects
c = Counter("abracadabra")
c.most_common(2)                # [('a', 5), ('b', 2)]
c["a"] - c["b"]                 # 3 — arithmetic on counts
c.total()                       # 11 — sum of all counts (3.10+)
Counter("aab") & Counter("abc") # intersection: Counter({'a': 1, 'b': 1})
Counter("aab") | Counter("abc") # union: Counter({'a': 2, 'b': 1, 'c': 1})

# defaultdict — dict with auto-generated default values
graph = defaultdict(list)
graph["a"].append("b")          # no KeyError, auto-creates []
freq = defaultdict(int)
freq["x"] += 1                  # starts at 0
tags = defaultdict(set)
tags["user"].add("admin")       # starts as set()

# deque — double-ended queue, O(1) append/pop on both ends
dq = deque([1, 2, 3], maxlen=5)
dq.appendleft(0)                # [0, 1, 2, 3]
dq.popleft()                    # 0
dq.rotate(1)                    # last element moves to front
dq.rotate(-1)                   # first element moves to back

# namedtuple — lightweight immutable record
Point = namedtuple("Point", ["x", "y"])
p = Point(3, 4)
p.x                             # 3
p._asdict()                     # {'x': 3, 'y': 4}
p._replace(x=10)               # Point(x=10, y=4)
```

## itertools

Use for efficient iteration patterns — combinatorics, grouping, slicing infinite sequences.

| Function | Description | Example |
|----------|-------------|---------|
| `batched(iter, n)` | Split into n-sized chunks (3.12+) | `batched("ABCDE", 2)` -> `('A','B'), ('C','D'), ('E',)` |
| `chain.from_iterable(iters)` | Flatten one level of nesting | `chain.from_iterable([[1,2],[3]])` -> `1,2,3` |
| `groupby(iter, key)` | Group consecutive items (must be sorted!) | Groups by key function |
| `islice(iter, start, stop, step)` | Slice any iterator | `islice(count(), 5, 10)` -> `5,6,7,8,9` |
| `combinations(iter, r)` | r-length combos, no repeat | `combinations("ABC", 2)` -> `AB, AC, BC` |
| `permutations(iter, r)` | r-length permutations | `permutations("AB", 2)` -> `AB, BA` |
| `product(iter, repeat=)` | Cartesian product | `product([0,1], repeat=3)` -> 8 tuples |
| `accumulate(iter, func)` | Running totals/reductions | `accumulate([1,2,3])` -> `1, 3, 6` |
| `repeat(x, n)` | Repeat x, n times | `repeat(7, 3)` -> `7, 7, 7` |
| `cycle(iter)` | Cycle forever | `cycle("AB")` -> `A, B, A, B, ...` |
| `count(start, step)` | Infinite counter | `count(10, 2)` -> `10, 12, 14, ...` |

```python
from itertools import batched, chain, groupby, islice, combinations, permutations, product, accumulate

# Examples
list(batched("ABCDEFG", 3))             # [('A','B','C'), ('D','E','F'), ('G',)]
list(chain.from_iterable([[1,2],[3,4]])) # [1, 2, 3, 4]
list(islice(range(100), 5, 15, 2))       # [5, 7, 9, 11, 13]
list(accumulate([1,2,3,4]))              # [1, 3, 6, 10]
list(accumulate([3,1,4,1], max))         # [3, 3, 4, 4]
```

## functools

Use for function transformation: caching, partial application, and reduction.

```python
from functools import reduce, lru_cache, cache, partial, total_ordering

# reduce — fold a sequence into a single value
product = reduce(lambda a, b: a * b, [1, 2, 3, 4])  # 24

# lru_cache / cache (cache = lru_cache(maxsize=None))
@cache
def fib(n):
    return n if n < 2 else fib(n-1) + fib(n-2)

@lru_cache(maxsize=128)     # bounded cache
def expensive(x, y):
    return compute(x, y)

# partial — freeze some arguments
int_from_hex = partial(int, base=16)
int_from_hex("ff")          # 255

# total_ordering — define __eq__ + one comparison, get the rest
@total_ordering
class Score:
    def __init__(self, val): self.val = val
    def __eq__(self, other): return self.val == other.val
    def __lt__(self, other): return self.val < other.val
```

## Sorting & Searching

Use for ordering data and efficient lookups in sorted sequences.

```python
from operator import attrgetter, itemgetter
import bisect, heapq

# sorted with key
sorted(words, key=str.lower)
sorted(pairs, key=lambda x: x[1])
sorted(objects, key=attrgetter("name"))
sorted(dicts, key=itemgetter("age"))

# Multi-key sort with tuple (secondary desc: negate numeric values)
sorted(students, key=lambda s: (s.grade, -s.age))

# Reverse sort
sorted(nums, reverse=True)

# For non-numeric desc sort: sort twice (stable sort preserves order)
# Or use functools.cmp_to_key for complex comparisons

# bisect — binary search on sorted list
idx = bisect.bisect_left(sorted_list, target)   # insertion point (left)
bisect.insort(sorted_list, new_val)             # insert maintaining order

# heapq (min-heap) — efficient top-N and priority queues
heapq.nlargest(3, data)
heapq.nsmallest(3, data, key=lambda x: x.score)
heapq.heappush(heap, (priority, item))
item = heapq.heappop(heap)      # pops smallest
```

## Regular Expressions

Use for pattern matching, text extraction, and substitution.

### Common Patterns

| Pattern | Matches |
|---------|---------|
| `\d` | Digit `[0-9]` |
| `\D` | Non-digit |
| `\w` | Word char `[a-zA-Z0-9_]` |
| `\W` | Non-word char |
| `\s` | Whitespace |
| `\S` | Non-whitespace |
| `.` | Any char (except newline) |
| `*` | 0 or more (greedy) |
| `+` | 1 or more (greedy) |
| `?` | 0 or 1 (greedy) |
| `*?`, `+?` | Non-greedy versions |
| `{n,m}` | Between n and m times |
| `^` | Start of string/line |
| `$` | End of string/line |
| `[abc]` | Character class |
| `[^abc]` | Negated class |
| `(...)` | Capture group |
| `(?:...)` | Non-capture group |
| `a\|b` | Alternation |
| `\b` | Word boundary |

```python
import re

# Core functions
m = re.search(r"\d+", "age: 42")     # first match anywhere
m.group()                              # '42'

m = re.match(r"\d+", "42 is the answer")  # match at START only
m.group()                              # '42'

re.findall(r"\d+", "3 cats and 4 dogs")  # ['3', '4']
list(re.finditer(r"\d+", text))          # list of Match objects

re.sub(r"\d+", "N", "3 cats 4 dogs")     # 'N cats N dogs'

# Named groups
m = re.search(r"(?P<year>\d{4})-(?P<month>\d{2})", "2024-03-15")
m.group("year")    # '2024'
m.groupdict()      # {'year': '2024', 'month': '03'}

# Flags
re.search(r"hello", text, re.IGNORECASE)
re.findall(r"^line", text, re.MULTILINE)   # ^ matches each line start

# Compile for reuse
pattern = re.compile(r"\b\w{4}\b")
pattern.findall("the quick brown fox")     # ['quick', 'brown']
```

## Async

Use for concurrent I/O-bound tasks (network requests, file I/O) without threads.

```python
import asyncio

# Basic async pattern
async def main():
    result = await fetch_data()

asyncio.run(main())      # entry point — runs the event loop

# gather — run coroutines concurrently, collect all results
results = await asyncio.gather(fetch(url1), fetch(url2), fetch(url3))

# TaskGroup (3.11+) — structured concurrency with better error handling
async with asyncio.TaskGroup() as tg:
    task1 = tg.create_task(fetch(url1))
    task2 = tg.create_task(fetch(url2))
# all tasks complete here; if any raises, all are cancelled

# timeout (3.11+)
async with asyncio.timeout(5.0):
    data = await slow_operation()

# async for — iterate over async generators/iterables
async for item in async_generator():
    process(item)

# async with — async context managers
async with aiohttp.ClientSession() as session:
    resp = await session.get(url)
```

## Type Hints

Use for documentation, IDE support, and static analysis with mypy/pyright.

```python
from typing import TypeVar, Generic, Callable
from collections.abc import Sequence, Mapping

# Basic types (3.9+ built-in generics)
x: int = 5
name: str = "Alice"
items: list[int] = [1, 2, 3]
lookup: dict[str, int] = {"a": 1}
maybe: int | None = None            # 3.10+ (replaces Optional[int])
either: int | str = 0               # 3.10+ (replaces Union[int, str])

# TypeVar & Generic
T = TypeVar("T")
def first(items: Sequence[T]) -> T:
    return items[0]

class Stack(Generic[T]):
    def push(self, item: T) -> None: ...
    def pop(self) -> T: ...

# Callable — specify function signatures
Handler = Callable[[int, str], bool]        # takes (int, str), returns bool
Decorator = Callable[[Callable], Callable]

# Sequence & Mapping — abstract (accept list/tuple, dict/etc.)
def process(items: Sequence[int]) -> Mapping[str, int]: ...

# type statement (3.12+) — type aliases
type Vector = list[float]
type Callback[T] = Callable[[T], None]
```

## Useful Built-ins

Quick reference for the most commonly used built-in functions.

| Function | Description | Example |
|----------|-------------|---------|
| `len(x)` | Length/size | `len([1,2,3])` -> `3` |
| `range(start, stop, step)` | Integer sequence | `range(0, 10, 2)` -> `0,2,4,6,8` |
| `enumerate(iter, start=0)` | Index + value pairs | `enumerate("ab")` -> `(0,'a'), (1,'b')` |
| `zip(*iters)` | Parallel iteration | `zip([1,2], "ab")` -> `(1,'a'), (2,'b')` |
| `map(fn, iter)` | Apply fn to each | `map(str, [1,2])` -> `'1', '2'` |
| `filter(fn, iter)` | Keep truthy results | `filter(None, [0,1,2])` -> `1, 2` |
| `sorted(iter, key=, reverse=)` | New sorted list | `sorted([3,1,2])` -> `[1,2,3]` |
| `reversed(seq)` | Reverse iterator | `reversed([1,2,3])` -> `3, 2, 1` |
| `any(iter)` | True if any truthy | `any([0, "", 1])` -> `True` |
| `all(iter)` | True if all truthy | `all([1, "a", [1]])` -> `True` |
| `min(iter, key=)` | Smallest value | `min("hello", key=ord)` -> `'e'` |
| `max(iter, key=)` | Largest value | `max([1,2,3])` -> `3` |
| `sum(iter, start=0)` | Sum of elements | `sum([1,2,3])` -> `6` |
| `abs(x)` | Absolute value | `abs(-5)` -> `5` |
| `round(x, n)` | Round to n decimals | `round(3.456, 2)` -> `3.46` |
| `isinstance(obj, type)` | Type check (with inheritance) | `isinstance([], list)` -> `True` |
| `hasattr(obj, name)` | Has attribute? | `hasattr(obj, "x")` -> `True/False` |
| `getattr(obj, name, default)` | Get attribute or default | `getattr(obj, "x", 0)` |
| `vars(obj)` | Object's `__dict__` | `vars(point)` -> `{'x': 1, 'y': 2}` |
| `dir(obj)` | List all attributes | Shows methods and properties |
