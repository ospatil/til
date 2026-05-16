---
layout: ../layouts/GistLayout.astro
tags: []
---

# State Management Guidelines

Table of Contents

1. [Overview](#overview)
2. [Quick Decision Guide](#quick-decision-guide)
3. [The Stack - Layer by Layer](#the-stack---layer-by-layer)
4. [Integration Patterns](#integration-patterns)
5. [Composite Atoms Deep Dive](#composite-atoms-deep-dive)
6. [File Organization](#file-organization)
7. [Best Practices & Anti-Patterns](#best-practices--anti-patterns)
8. [Performance Optimization](#performance-optimization)
9. [Testing](#testing)
10. [Migration Guide](#migration-guide)
11. [Quick Reference](#quick-reference)

---

Overview

### Our Stack

Our state management stack consists of five distinct layers, each with a specific purpose:

| Layer | Tool | Purpose |
|-------|------|---------|
| **Layer 1** | TanStack Router | Routing, URL state, data loading |
| **Layer 2** | TanStack Query | Server state, API calls, caching |
| **Layer 3** | Jotai | Global client state, shared UI state |
| **Layer 4** | React Hooks | Local component state (useState, useMemo, useCallback) |
| **Layer 5** | React Hook Form | Form state and validation |

### Core Principles

1. **Single Source of Truth**: Each piece of state lives in exactly one layer
2. **Start Local**: Begin with useState and only lift to higher layers when sharing is needed
3. **Use the Right Tool**: Each tool excels at its specific job
4. **Minimize Re-renders**: Structure atoms granularly, use selectors appropriately

---

Quick Decision Guide

### Decision Tree

```
Does this state need to be in the URL (shareable/bookmarkable)?
├─ YES → TanStack Router (search params)
│
└─ NO → Is this data from an API?
    ├─ YES → TanStack Query
    │
    └─ NO → Is this a form with validation?
        ├─ YES → React Hook Form
        │
        └─ NO → Does it need to be shared across components?
            ├─ YES → Jotai
            │
            └─ NO → Local component state
                ├─ Simple state → useState
                ├─ Derived/computed → useMemo
                └─ Callbacks → useCallback
```

### Quick Reference Table

| State Type | Tool | Example |
|------------|------|---------|
| Route parameters | TanStack Router | `/products/:id` |
| Search parameters | TanStack Router | `?page=1&filter=active` |
| API data (GET) | TanStack Query | User list, product details |
| API mutations (POST/PUT/DELETE) | TanStack Query | Create user, update product |
| Form inputs & validation | React Hook Form | Login form, user profile editor |
| UI state (local to component) | useState | Dropdown open/closed, hover state |
| Derived state (local) | useMemo | Filtered list, sorted data within component |
| Callbacks (local) | useCallback | Event handlers for optimized children |
| UI state (shared across components) | Jotai | Modal open/closed, sidebar state, theme |
| Selected items (shared) | Jotai | Selected row in table, active tab |
| Client-side filters (shared) | Jotai | Global search filter, view mode toggle |
| Derived/computed state (shared) | Jotai | Filtered list used by multiple components |

---

The Stack - Layer by Layer

### Layer 1: URL State (TanStack Router)

#### When to Use
- Page numbers, sort order, filters
- Selected tab or view mode (if shareable)
- Search queries
- Any state that makes the page bookmarkable

#### Setup

```typescript
// routes/products.tsx
import { createFileRoute } from '@tanstack/react-router'
import { z } from 'zod'

const productSearchSchema = z.object({
  page: z.number().catch(1),
  category: z.string().catch('all'),
  sort: z.enum(['name', 'price', 'date']).catch('name'),
  search: z.string().optional()
})

export const Route = createFileRoute('/products')({
  validateSearch: (search) => productSearchSchema.parse(search),
  loaderDeps: ({ search }) => ({ search }),
  loader: ({ deps: { search } }) => {
    return queryClient.ensureQueryData({
      queryKey: ['products', search],
      queryFn: () => api.fetchProducts(search)
    })
  }
})
```

#### Usage in Components

```typescript
function ProductsPage() {
  const navigate = Route.useNavigate()
  const { page, category, sort, search } = Route.useSearch()
  
  const updateCategory = (newCategory: string) => {
    navigate({
      search: (prev) => ({ ...prev, category: newCategory, page: 1 })
    })
  }
  
  return (
    <div>
      <CategoryFilter value={category} onChange={updateCategory} />
      <Pagination page={page} onChange={(p) => navigate({ search: (prev) => ({ ...prev, page: p }) })} />
    </div>
  )
}
```

---

### Layer 2: Server State (TanStack Query)

#### When to Use
- All API calls (GET, POST, PUT, DELETE)
- Data that comes from a server
- Data that needs caching or background refetching
- Paginated or infinite scroll data

#### Setup

```typescript
// lib/queryClient.ts
import { QueryClient } from '@tanstack/react-query'

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 60 * 1000, // 1 minute
      retry: 1,
    },
  },
})

// App.tsx
import { QueryClientProvider } from '@tanstack/react-query'

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      {/* Your app */}
    </QueryClientProvider>
  )
}
```

#### Basic Query

```typescript
// hooks/useProducts.ts
import { useQuery } from '@tanstack/react-query'

export function useProducts(filters: ProductFilters) {
  return useQuery({
    queryKey: ['products', filters],
    queryFn: () => api.fetchProducts(filters),
    staleTime: 5 * 60 * 1000, // 5 minutes
  })
}

// In component
function ProductList() {
  const { search, category } = Route.useSearch()
  const { data, isLoading, error } = useProducts({ search, category })
  
  if (isLoading) return <Spinner />
  if (error) return <Error message={error.message} />
  
  return <ProductGrid products={data} />
}
```

#### Mutations

```typescript
// hooks/useUpdateProduct.ts
import { useMutation, useQueryClient } from '@tanstack/react-query'

export function useUpdateProduct() {
  const queryClient = useQueryClient()
  
  return useMutation({
    mutationFn: (data: UpdateProductData) => 
      api.updateProduct(data.id, data),
    
    onMutate: async (newProduct) => {
      await queryClient.cancelQueries({ queryKey: ['product', newProduct.id] })
      const previous = queryClient.getQueryData(['product', newProduct.id])
      queryClient.setQueryData(['product', newProduct.id], newProduct)
      return { previous }
    },
    
    onError: (err, newProduct, context) => {
      queryClient.setQueryData(['product', newProduct.id], context?.previous)
    },
    
    onSuccess: (data, variables) => {
      queryClient.invalidateQueries({ queryKey: ['product', variables.id] })
      queryClient.invalidateQueries({ queryKey: ['products'] })
    },
  })
}
```

---

### Layer 3: Client State (Jotai)

#### When to Use
- UI state that needs to be shared across multiple components
- State accessed by components at different levels of the tree
- Selected items, active tabs (when shared)
- Client-side filters/search that multiple components need
- Derived state from server data that's used in multiple places
- Theme, user preferences

**Key principle:** Use Jotai when state needs to be accessed by components that don't have a direct parent-child relationship, or when prop drilling becomes cumbersome (2+ levels deep).

#### Setup

```typescript
// App.tsx
import { Provider as JotaiProvider } from 'jotai'

function App() {
  return (
    <JotaiProvider>
      <QueryClientProvider client={queryClient}>
        {/* Your app */}
      </QueryClientProvider>
    </JotaiProvider>
  )
}
```

#### Simple Atoms

```typescript
// atoms/ui.ts
import { atom } from 'jotai'

export const sidebarOpenAtom = atom(false)
export const themeAtom = atom<'light' | 'dark'>('light')
export const selectedProductIdAtom = atom<string | null>(null)

// Usage
function Sidebar() {
  const [isOpen, setIsOpen] = useAtom(sidebarOpenAtom)
  return <aside className={isOpen ? 'open' : 'closed'}>...</aside>
}

function Header() {
  const setIsOpen = useSetAtom(sidebarOpenAtom)
  return <button onClick={() => setIsOpen(true)}>Open Sidebar</button>
}
```

#### Derived Atoms

```typescript
// atoms/products.ts
export const selectedProductIdAtom = atom<string | null>(null)

export const selectedProductAtom = atom((get) => {
  const selectedId = get(selectedProductIdAtom)
  if (!selectedId) return null
  
  const products = queryClient.getQueryData<Product[]>(['products'])
  return products?.find(p => p.id === selectedId) ?? null
})
```

#### Atoms with Actions

```typescript
// atoms/cart.ts
import { atom } from 'jotai'

type CartItem = { id: string; quantity: number }

export const cartItemsAtom = atom<CartItem[]>([])

export const addToCartAtom = atom(
  null,
  (get, set, productId: string) => {
    const items = get(cartItemsAtom)
    const existing = items.find(item => item.id === productId)
    
    if (existing) {
      set(cartItemsAtom, items.map(item =>
        item.id === productId
          ? { ...item, quantity: item.quantity + 1 }
          : item
      ))
    } else {
      set(cartItemsAtom, [...items, { id: productId, quantity: 1 }])
    }
  }
)
```

#### Atoms with Persistence

```typescript
// atoms/preferences.ts
import { atomWithStorage } from 'jotai/utils'

export const themeAtom = atomWithStorage<'light' | 'dark'>('theme', 'light')
export const languageAtom = atomWithStorage<'en' | 'fr'>('language', 'en')
```

#### Atoms for Lists

```typescript
// atoms/todos.ts
import { atom } from 'jotai'
import { splitAtom } from 'jotai/utils'

type Todo = { id: string; text: string; done: boolean }

export const todosAtom = atom<Todo[]>([])
export const todoAtomsAtom = splitAtom(todosAtom)

// Usage
function TodoList() {
  const [todoAtoms] = useAtom(todoAtomsAtom)
  
  return (
    <>
      {todoAtoms.map((todoAtom) => (
        <TodoItem key={`${todoAtom}`} todoAtom={todoAtom} />
      ))}
    </>
  )
}

function TodoItem({ todoAtom }: { todoAtom: PrimitiveAtom<Todo> }) {
  const [todo, setTodo] = useAtom(todoAtom)
  // Only THIS todo re-renders when changed
  
  return (
    <div>
      <input
        type="checkbox"
        checked={todo.done}
        onChange={(e) => setTodo({ ...todo, done: e.target.checked })}
      />
      {todo.text}
    </div>
  )
}
```

---

### Layer 4: Local Component State (React Hooks)

#### When to Use
- State used only within a single component
- UI state that doesn't need to be shared
- Temporary state during user interactions
- Derived computations from local state

#### useState for Simple State

```typescript
function Dropdown() {
  const [isOpen, setIsOpen] = useState(false)
  
  return (
    <div>
      <button onClick={() => setIsOpen(!isOpen)}>Toggle</button>
      {isOpen && <DropdownMenu />}
    </div>
  )
}

function SearchInput() {
  const [query, setQuery] = useState('')
  
  return (
    <input
      value={query}
      onChange={(e) => setQuery(e.target.value)}
      placeholder="Search..."
    />
  )
}
```

#### useMemo for Derived State

```typescript
function ProductList({ products }: { products: Product[] }) {
  const [searchQuery, setSearchQuery] = useState('')
  const [sortBy, setSortBy] = useState<'name' | 'price'>('name')
  
  // Only recalculates when dependencies change
  const filteredAndSortedProducts = useMemo(() => {
    let result = products
    
    if (searchQuery) {
      result = result.filter(p => 
        p.name.toLowerCase().includes(searchQuery.toLowerCase())
      )
    }
    
    result = [...result].sort((a, b) => {
      if (sortBy === 'name') return a.name.localeCompare(b.name)
      return a.price - b.price
    })
    
    return result
  }, [products, searchQuery, sortBy])
  
  return (
    <div>
      <input value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} />
      <select value={sortBy} onChange={(e) => setSortBy(e.target.value as any)}>
        <option value="name">Name</option>
        <option value="price">Price</option>
      </select>
      {filteredAndSortedProducts.map(p => <ProductCard key={p.id} product={p} />)}
    </div>
  )
}
```

**When to use useMemo:**
- Expensive computations (filtering/mapping large arrays)
- Values passed to `React.memo` child components
- Objects/arrays used in dependency arrays

**When NOT to use:**
```typescript
// ❌ Overkill for cheap calculations
const doubled = useMemo(() => count * 2, [count])

// ✅ Just compute directly
const doubled = count * 2
```

#### useCallback for Stable Functions

```typescript
function ParentComponent() {
  const [items, setItems] = useState<Item[]>([])
  
  const handleItemClick = useCallback((itemId: string) => {
    console.log('Clicked item:', itemId)
  }, [])
  
  const handleItemDelete = useCallback((itemId: string) => {
    setItems(items => items.filter(item => item.id !== itemId))
  }, [])
  
  return (
    <div>
      {items.map(item => (
        <ExpensiveChild
          key={item.id}
          item={item}
          onClick={handleItemClick}
          onDelete={handleItemDelete}
        />
      ))}
    </div>
  )
}

const ExpensiveChild = React.memo(({ item, onClick, onDelete }) => {
  return (
    <div onClick={() => onClick(item.id)}>
      {item.name}
      <button onClick={() => onDelete(item.id)}>Delete</button>
    </div>
  )
})
```

**When to use useCallback:**
- Callbacks passed to `React.memo` children
- Callbacks used as dependencies in other hooks

**When NOT to use:**
```typescript
// ❌ No benefit if child isn't memoized
function Parent() {
  const handleClick = useCallback(() => {}, [])
  return <RegularChild onClick={handleClick} />
}

// ✅ Just use regular function
function Parent() {
  const handleClick = () => {}
  return <RegularChild onClick={handleClick} />
}
```

#### When to Move from Local to Jotai

```typescript
// ❌ Prop drilling through multiple levels
function GrandParent() {
  const [theme, setTheme] = useState('light')
  return <Parent theme={theme} setTheme={setTheme} />
}

function Parent({ theme, setTheme }) {
  return <Child theme={theme} setTheme={setTheme} />
}

function Child({ theme, setTheme }) {
  return <ThemeToggle theme={theme} onToggle={setTheme} />
}

// ✅ Use Jotai instead
const themeAtom = atom<'light' | 'dark'>('light')

function GrandParent() {
  return <Parent />
}

function ThemeToggle() {
  const [theme, setTheme] = useAtom(themeAtom)
  return <button onClick={() => setTheme(theme === 'light' ? 'dark' : 'light')} />
}
```

**Migration threshold:** If you're passing state through 2+ component levels, consider Jotai.

---

### Layer 5: Form State (React Hook Form)

#### When to Use
- Any form with 3+ fields
- Forms with validation requirements
- Forms with complex field dependencies
- Dynamic form fields (field arrays)

#### Basic Form

```typescript
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'

const loginSchema = z.object({
  email: z.string().email('Invalid email'),
  password: z.string().min(8, 'Password must be at least 8 characters'),
})

type LoginFormData = z.infer<typeof loginSchema>

function LoginForm() {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting }
  } = useForm<LoginFormData>({
    resolver: zodResolver(loginSchema),
  })
  
  const onSubmit = async (data: LoginFormData) => {
    await api.login(data)
  }
  
  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <div>
        <input {...register('email')} placeholder="Email" />
        {errors.email && <span>{errors.email.message}</span>}
      </div>
      
      <div>
        <input {...register('password')} type="password" placeholder="Password" />
        {errors.password && <span>{errors.password.message}</span>}
      </div>
      
      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? 'Logging in...' : 'Login'}
      </button>
    </form>
  )
}
```

#### Form with Mutation

```typescript
function CreateProductForm() {
  const navigate = useNavigate()
  const { register, handleSubmit, formState: { errors } } = useForm<ProductFormData>({
    resolver: zodResolver(productSchema),
  })
  
  const createProduct = useMutation({
    mutationFn: api.createProduct,
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['products'] })
      navigate({ to: '/products/$id', params: { id: data.id } })
    },
  })
  
  return (
    <form onSubmit={handleSubmit((data) => createProduct.mutate(data))}>
      <input {...register('name')} />
      {errors.name && <span>{errors.name.message}</span>}
      
      <button type="submit" disabled={createProduct.isPending}>
        {createProduct.isPending ? 'Creating...' : 'Create Product'}
      </button>
      
      {createProduct.error && <div>Error: {createProduct.error.message}</div>}
    </form>
  )
}
```

#### Form with Default Values from Query

```typescript
function EditProductForm({ productId }: { productId: string }) {
  const { data: product, isLoading } = useQuery({
    queryKey: ['product', productId],
    queryFn: () => api.fetchProduct(productId),
  })
  
  const { register, handleSubmit, reset } = useForm<ProductFormData>({
    resolver: zodResolver(productSchema),
  })
  
  useEffect(() => {
    if (product) {
      reset({
        name: product.name,
        price: product.price,
        description: product.description,
      })
    }
  }, [product, reset])
  
  const updateProduct = useMutation({
    mutationFn: (data: ProductFormData) => api.updateProduct(productId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['product', productId] })
    },
  })
  
  if (isLoading) return <Spinner />
  
  return <form onSubmit={handleSubmit((data) => updateProduct.mutate(data))}>...</form>
}
```

---

Integration Patterns

### Pattern 1: Router → Query → Component

```typescript
// routes/products.$id.tsx
export const Route = createFileRoute('/products/$id')({
  loader: ({ params }) => {
    return queryClient.ensureQueryData({
      queryKey: ['product', params.id],
      queryFn: () => api.fetchProduct(params.id),
    })
  },
})

function ProductPage() {
  const { id } = Route.useParams()
  const { data: product } = useQuery({
    queryKey: ['product', id],
    queryFn: () => api.fetchProduct(id),
  })
  
  return <ProductDetails product={product} />
}
```

### Pattern 2: Router Search Params → Query

```typescript
function ProductsPage() {
  const { page, category, sort } = Route.useSearch()
  
  const { data: products } = useQuery({
    queryKey: ['products', { page, category, sort }],
    queryFn: () => api.fetchProducts({ page, category, sort }),
  })
  
  return <ProductList products={products} />
}
```

### Pattern 3: Query Data → Jotai Atoms

```typescript
// Bridge component
function ProductDataBridge() {
  const { data: products } = useQuery({
    queryKey: ['products'],
    queryFn: api.fetchProducts,
  })
  
  const setProducts = useSetAtom(productsCacheAtom)
  
  useEffect(() => {
    if (products) setProducts(products)
  }, [products, setProducts])
  
  return null
}

// Or access query cache directly in atoms
export const selectedProductAtom = atom((get) => {
  const selectedId = get(selectedProductIdAtom)
  const products = queryClient.getQueryData<Product[]>(['products'])
  return products?.find(p => p.id === selectedId) ?? null
})
```

### Pattern 4: URL State + Jotai Client State

```typescript
function ProductsPage() {
  const navigate = Route.useNavigate()
  
  // URL state - affects server data
  const { page, category } = Route.useSearch()
  
  // Server state
  const { data: products } = useQuery({
    queryKey: ['products', { page, category }],
    queryFn: () => api.fetchProducts({ page, category }),
  })
  
  // Client state - UI only
  const [viewMode, setViewMode] = useAtom(viewModeAtom)
  const [selectedId, setSelectedId] = useAtom(selectedProductIdAtom)
  
  const handleCategoryChange = (newCategory: string) => {
    navigate({ search: (prev) => ({ ...prev, category: newCategory, page: 1 }) })
    setSelectedId(null) // Clear client state
  }
  
  return (
    <div>
      <CategoryFilter value={category} onChange={handleCategoryChange} />
      <ViewModeToggle value={viewMode} onChange={setViewMode} />
      <ProductGrid products={products} viewMode={viewMode} selectedId={selectedId} onSelect={setSelectedId} />
    </div>
  )
}
```

### Pattern 5: Multi-Step Form with Jotai + RHF

```typescript
// atoms/checkout.ts
export const checkoutStepAtom = atom<1 | 2 | 3>(1)
export const shippingDataAtom = atom<ShippingData | null>(null)
export const paymentDataAtom = atom<PaymentData | null>(null)

// Step 1
function ShippingStep() {
  const [, setStep] = useAtom(checkoutStepAtom)
  const [, setShippingData] = useAtom(shippingDataAtom)
  const { register, handleSubmit } = useForm<ShippingData>()
  
  const onSubmit = (data: ShippingData) => {
    setShippingData(data)
    setStep(2)
  }
  
  return <form onSubmit={handleSubmit(onSubmit)}>...</form>
}

// Step 3: Confirmation
function ConfirmationStep() {
  const shippingData = useAtomValue(shippingDataAtom)
  const paymentData = useAtomValue(paymentDataAtom)
  
  const placeOrder = useMutation({
    mutationFn: () => api.placeOrder({ shippingData, paymentData }),
  })
  
  return <button onClick={() => placeOrder.mutate()}>Place Order</button>
}
```

---

Composite Atoms Deep Dive

### The Core Issue

**Jotai tracks atoms, not object properties.** This is critical to understand:

```typescript
// This is ONE reactive unit
const userAtom = atom({ name: 'Alice', age: 30, email: 'alice@example.com' })

// Any field change creates a new object → triggers re-render in ALL components using this atom
setUser({ ...user, name: 'Bob' })
```

### When to Split vs Composite

#### ✅ Use Separate Atoms When:

**1. Fields are logically independent**
```typescript
const themeAtom = atom('dark')
const userNameAtom = atom('Alice')
```

**2. Fields update independently**
```typescript
const nameAtom = atom('Alice')
const emailAtom = atom('alice@example.com')
```

**3. Different components consume different fields**
```typescript
function Header() {
  const name = useAtomValue(nameAtom)
  // ✅ Only re-renders when name changes
}

function EmailSection() {
  const email = useAtomValue(emailAtom)
  // ✅ Only re-renders when email changes
}
```

#### ✅ Use Composite Atoms When:

**1. Fields always update together**
```typescript
const mousePositionAtom = atom({ x: 0, y: 0 })
```

**2. Data comes from external API**
```typescript
const userDataAtom = atom(async () => {
  const response = await fetch('/api/user')
  return response.json()
})
```

**3. Fields have tight coupling**
```typescript
const priceAtom = atom({ amount: 99.99, currency: 'USD' })
```

### Pattern 1: Split at Definition (Recommended)

```typescript
// atoms/user.ts

// Define granular atoms
export const userNameAtom = atom('Alice')
export const userEmailAtom = atom('alice@example.com')
export const userAgeAtom = atom(30)

// Composite derived atom for convenience
export const userAtom = atom((get) => ({
  name: get(userNameAtom),
  email: get(userEmailAtom),
  age: get(userAgeAtom)
}))

// Write helper for batch updates
export const updateUserAtom = atom(
  null,
  (get, set, update: Partial<User>) => {
    if (update.name !== undefined) set(userNameAtom, update.name)
    if (update.email !== undefined) set(userEmailAtom, update.email)
    if (update.age !== undefined) set(userAgeAtom, update.age)
  }
)

// Usage: Granular reads
function NameDisplay() {
  const name = useAtomValue(userNameAtom)
  // ✅ Only re-renders when name changes
  return <h1>{name}</h1>
}

// Usage: Full object when needed
function UserCard() {
  const user = useAtomValue(userAtom)
  // Re-renders when ANY field changes - expected here
  return <div>{user.name} - {user.email}</div>
}

// Usage: Batch updates
function EditUserModal() {
  const updateUser = useSetAtom(updateUserAtom)
  const handleSave = (data: Partial<User>) => updateUser(data)
}
```

### Pattern 2: Use selectAtom for Existing Composite

```typescript
import { selectAtom } from 'jotai/utils'

// Composite atom from API
const apiUserAtom = atom({
  id: '1',
  name: 'Alice',
  email: 'alice@example.com',
  age: 30
})

// Create granular selectors
export const userNameAtom = selectAtom(apiUserAtom, (user) => user.name)
export const userEmailAtom = selectAtom(apiUserAtom, (user) => user.email)

function NameDisplay() {
  const name = useAtomValue(userNameAtom)
  // ✅ Only re-renders when name changes
  return <div>{name}</div>
}

// For writes, update the full object
function UpdateProfile() {
  const [user, setUser] = useAtom(apiUserAtom)
  const updateName = (newName: string) => {
    setUser({ ...user, name: newName })
  }
}
```

### Pattern 3: Use focusAtom for Read + Write

```typescript
import { focusAtom } from 'jotai-optics'

const userAtom = atom({ name: 'Alice', email: 'alice@example.com', age: 30 })

// Focused atoms with read AND write
export const userNameAtom = focusAtom(userAtom, (optic) => optic.prop('name'))
export const userEmailAtom = focusAtom(userAtom, (optic) => optic.prop('email'))

function NameEditor() {
  const [name, setName] = useAtom(userNameAtom)
  // ✅ Only re-renders when name changes
  // ✅ setName automatically updates just the name field
  
  return <input value={name} onChange={(e) => setName(e.target.value)} />
}
```

**Note:** Requires `jotai-optics` package

### Pattern 4: Bridge API Data

```typescript
// Granular atoms
export const userNameAtom = atom('Alice')
export const userEmailAtom = atom('alice@example.com')

// Bridge component
function UserDataBridge() {
  const { data: user } = useQuery({
    queryKey: ['user'],
    queryFn: api.fetchUser
  })
  
  const setName = useSetAtom(userNameAtom)
  const setEmail = useSetAtom(userEmailAtom)
  
  useEffect(() => {
    if (user) {
      setName(user.name)
      setEmail(user.email)
    }
  }, [user, setName, setEmail])
  
  return null
}
```

### Real-World Example: Shopping Cart

```typescript
import { splitAtom } from 'jotai/utils'

type CartItem = { id: string; name: string; quantity: number; price: number }

export const cartItemsAtom = atom<CartItem[]>([])
export const cartItemAtomsAtom = splitAtom(cartItemsAtom)

export const cartTotalItemsAtom = atom((get) => {
  const items = get(cartItemsAtom)
  return items.reduce((sum, item) => sum + item.quantity, 0)
})

export const cartTotalPriceAtom = atom((get) => {
  const items = get(cartItemsAtom)
  return items.reduce((sum, item) => sum + item.quantity * item.price, 0)
})

function CartList() {
  const [itemAtoms] = useAtom(cartItemAtomsAtom)
  return (
    <>
      {itemAtoms.map((itemAtom) => (
        <CartItem key={`${itemAtom}`} itemAtom={itemAtom} />
      ))}
    </>
  )
}

function CartItem({ itemAtom }: { itemAtom: PrimitiveAtom<CartItem> }) {
  const [item, setItem] = useAtom(itemAtom)
  // ✅ Only THIS item re-renders when its quantity changes
  
  return (
    <div>
      {item.name} - ${item.price}
      <button onClick={() => setItem({ ...item, quantity: item.quantity + 1 })}>+</button>
      <span>{item.quantity}</span>
      <button onClick={() => setItem({ ...item, quantity: item.quantity - 1 })}>-</button>
    </div>
  )
}

function CartSummary() {
  const totalItems = useAtomValue(cartTotalItemsAtom)
  const totalPrice = useAtomValue(cartTotalPriceAtom)
  return <div>Items: {totalItems} | Total: ${totalPrice.toFixed(2)}</div>
}
```

### Decision Flowchart

```
Do I control the atom structure from the start?
├─ YES → Split into separate atoms
│   const nameAtom = atom('Alice')
│   const emailAtom = atom('alice@...')
│
└─ NO (API data) → Use selectAtom or focusAtom
    ├─ Read-only → selectAtom
    └─ Need writes → focusAtom

Do fields always update together?
├─ YES → Composite is OK
│   const positionAtom = atom({ x: 0, y: 0 })
│
└─ NO → Split into separate atoms

Do different components need different fields?
├─ YES → Split or use selectAtom
└─ NO → Composite is OK
```

---

File Organization

### Recommended Structure

```
src/
  routes/                      # TanStack Router file-based routing
    __root.tsx
    index.tsx
    products/
      index.tsx              # /products
      $id.tsx                # /products/:id
      create.tsx
    users/
      index.tsx
      $id/
        index.tsx            # /users/:id
        edit.tsx
  
  api/                       # API client functions
    client.ts                # Axios/fetch setup
    products.ts
    users.ts
  
  hooks/
    queries/                 # TanStack Query hooks
      useProducts.ts
      useProduct.ts
    mutations/
      useCreateProduct.ts
      useUpdateProduct.ts
  
  atoms/                     # Jotai atoms (shared state only)
    ui.ts                    # Global UI state
    products.ts              # Product client state
    cart.ts
    preferences.ts
  
  components/
    ui/                      # Reusable UI components
      Button.tsx
      Modal.tsx
    products/
      ProductCard.tsx
      ProductGrid.tsx
      ProductForm.tsx        # With React Hook Form
    layout/
      Header.tsx
      Sidebar.tsx
  
  lib/
    queryClient.ts
    router.ts
```

### Naming Conventions

**Files:**
- Routes: TanStack Router conventions (`$id.tsx`, `index.tsx`)
- API functions: `products.ts` (plural)
- Query hooks: `useProducts.ts`, `useProduct.ts`
- Mutation hooks: `useCreateProduct.ts`, `useUpdateProduct.ts`
- Atoms: `products.ts`, `ui.ts` (domain-based)
- Components: PascalCase (`ProductCard.tsx`)

**Variables:**
- Atoms: `camelCaseAtom` (e.g., `selectedProductIdAtom`)
- Query hooks: `use<Resource>` (e.g., `useProducts`)
- Mutation hooks: `use<Action><Resource>` (e.g., `useCreateProduct`)
- API functions: `fetch<Resource>`, `create<Resource>`

---

Best Practices & Anti-Patterns

### ✅ DO: Keep State in the Right Layer

```typescript
function ProductPage() {
  // URL - affects data
  const { page } = Route.useSearch()
  
  // Server - the data
  const { data: products } = useQuery({
    queryKey: ['products', page],
    queryFn: () => api.fetchProducts(page),
  })
  
  // Shared client state
  const [viewMode] = useAtom(viewModeAtom)
  
  // Local state
  const [isDropdownOpen, setIsDropdownOpen] = useState(false)
  
  // Local derived state
  const visibleProducts = useMemo(() => products?.slice(0, 10) ?? [], [products])
}
```

### ❌ DON'T: Duplicate State Across Layers

```typescript
// ❌ Bad - duplicating query data in Jotai
const productsAtom = atom<Product[]>([])

function Component() {
  const { data } = useQuery({
    queryKey: ['products'],
    queryFn: api.fetchProducts,
  })
  const [, setProducts] = useAtom(productsAtom)
  
  useEffect(() => {
    if (data) setProducts(data) // Unnecessary!
  }, [data])
}

// ✅ Good - just use query data
function Component() {
  const { data: products } = useQuery({
    queryKey: ['products'],
    queryFn: api.fetchProducts,
  })
}
```

### ❌ DON'T: Put API Data in Jotai

```typescript
// ❌ Bad - managing server state in Jotai
const usersAtom = atom<User[]>([])

const fetchUsersAtom = atom(null, async (get, set) => {
  const users = await api.fetchUsers()
  set(usersAtom, users)
})

// ✅ Good - use TanStack Query
function Component() {
  const { data: users } = useQuery({
    queryKey: ['users'],
    queryFn: api.fetchUsers,
  })
}
```

### ❌ DON'T: Use Jotai for Purely Local State

```typescript
// ❌ Bad
const dropdownOpenAtom = atom(false)

function Dropdown() {
  const [isOpen, setIsOpen] = useAtom(dropdownOpenAtom)
}

// ✅ Good
function Dropdown() {
  const [isOpen, setIsOpen] = useState(false)
}
```

### ✅ DO: Split Jotai Atoms Granularly

```typescript
// ✅ Good
const nameAtom = atom('')
const emailAtom = atom('')

function NameDisplay() {
  const name = useAtomValue(nameAtom)
  // Only re-renders when name changes
}

// ❌ Bad - monolithic atom
const userAtom = atom({ name: '', email: '', age: 0, settings: {} })

function NameDisplay() {
  const user = useAtomValue(userAtom)
  // Re-renders when ANY field changes!
  return <div>{user.name}</div>
}
```

### ✅ DO: Handle All Query States

```typescript
// ✅ Good
function ProductList() {
  const { data, isLoading, error, isError } = useQuery({
    queryKey: ['products'],
    queryFn: api.fetchProducts,
  })
  
  if (isLoading) return <Spinner />
  if (isError) return <Error message={error.message} />
  if (!data) return <Empty />
  
  return <ProductGrid products={data} />
}

// ❌ Bad - no error handling
function ProductList() {
  const { data } = useQuery({
    queryKey: ['products'],
    queryFn: api.fetchProducts,
  })
  
  return <ProductGrid products={data} /> // Crashes if error!
}
```

### ✅ DO: Invalidate Queries After Mutations

```typescript
// ✅ Good
const createProduct = useMutation({
  mutationFn: api.createProduct,
  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: ['products'] })
  },
})

// ❌ Bad - stale cache
const createProduct = useMutation({
  mutationFn: api.createProduct,
  // Missing onSuccess - list won't update!
})
```

### ✅ DO: Use URL State for Shareable Filters

```typescript
// ✅ Good - filters in URL
function ProductsPage() {
  const { category, sort } = Route.useSearch()
  // Users can bookmark/share this view
}

// ❌ Bad - filters only in Jotai
const categoryAtom = atom('electronics')
// Can't share or bookmark
```

### ❌ DON'T: Over-optimize with useCallback

```typescript
// ❌ Bad - unnecessary overhead
function Component() {
  const handleClick = useCallback(() => {
    console.log('clicked')
  }, [])
  
  return <RegularButton onClick={handleClick} /> // Child not memoized
}

// ✅ Good - simple function
function Component() {
  const handleClick = () => console.log('clicked')
  return <RegularButton onClick={handleClick} />
}
```

---

Performance Optimization

### 1. Memoize Expensive Computations in Atoms

```typescript
// ✅ Derived atoms are automatically memoized
const expensiveComputationAtom = atom((get) => {
  const items = get(itemsAtom)
  const filter = get(filterAtom)
  return items.filter(item => complexFilter(item, filter))
})
```

### 2. Use Query `select` for Partial Data

```typescript
// ✅ Only re-render when name changes
function ProductName({ id }: { id: string }) {
  const name = useQuery({
    queryKey: ['product', id],
    queryFn: () => api.fetchProduct(id),
    select: (product) => product.name,
  })
  
  return <div>{name.data}</div>
}
```

### 3. Split Large Atoms

```typescript
// ❌ Bad
const settingsAtom = atom({ theme: 'light', language: 'en', /* 20 more */ })

// ✅ Good
const themeAtom = atom('light')
const languageAtom = atom('en')
```

### 4. Use `staleTime` for Static Data

```typescript
const { data: categories } = useQuery({
  queryKey: ['categories'],
  queryFn: api.fetchCategories,
  staleTime: Infinity, // Rarely changes
})
```

### 5. Prefetch on Hover

```typescript
function ProductLink({ productId }: { productId: string }) {
  const queryClient = useQueryClient()
  
  const prefetch = () => {
    queryClient.prefetchQuery({
      queryKey: ['product', productId],
      queryFn: () => api.fetchProduct(productId),
    })
  }
  
  return (
    <Link
      to="/products/$id"
      params={{ id: productId }}
      onMouseEnter={prefetch}
    >
      View Product
    </Link>
  )
}
```

---

Testing

### Testing TanStack Query Hooks

```typescript
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  })
  
  return ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={queryClient}>
      {children}
    </QueryClientProvider>
  )
}

test('fetches products', async () => {
  const { result } = renderHook(() => useProducts(), {
    wrapper: createWrapper(),
  })
  
  expect(result.current.isLoading).toBe(true)
  await waitFor(() => expect(result.current.isSuccess).toBe(true))
  expect(result.current.data).toHaveLength(3)
})
```

### Testing Jotai Atoms

```typescript
import { createStore } from 'jotai'

test('selectedProductAtom derives from selectedProductIdAtom', () => {
  const store = createStore()
  
  queryClient.setQueryData(['products'], [
    { id: '1', name: 'Product 1' },
    { id: '2', name: 'Product 2' },
  ])
  
  store.set(selectedProductIdAtom, '1')
  
  const selected = store.get(selectedProductAtom)
  expect(selected).toEqual({ id: '1', name: 'Product 1' })
})
```

### Testing Forms

```typescript
import { render, screen, userEvent } from '@testing-library/react'

test('validates required fields', async () => {
  const onSubmit = jest.fn()
  render(<ProductForm onSubmit={onSubmit} />)
  
  await userEvent.click(screen.getByRole('button', { name: /submit/i }))
  
  expect(screen.getByText(/name is required/i)).toBeInTheDocument()
  expect(onSubmit).not.toHaveBeenCalled()
})
```

---

Migration Guide

### Converting useState to Jotai

```typescript
// Before
function ParentComponent() {
  const [selectedId, setSelectedId] = useState<string | null>(null)
  
  return (
    <>
      <ProductList onSelect={setSelectedId} />
      <ProductDetails selectedId={selectedId} />
    </>
  )
}

// After
export const selectedProductIdAtom = atom<string | null>(null)

function ParentComponent() {
  return (
    <>
      <ProductList />
      <ProductDetails />
    </>
  )
}

function ProductList() {
  const setSelectedId = useSetAtom(selectedProductIdAtom)
  // No props needed
}
```

### Converting Manual Fetching to TanStack Query

```typescript
// Before
function ProductList() {
  const [products, setProducts] = useState<Product[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<Error | null>(null)
  
  useEffect(() => {
    setLoading(true)
    api.fetchProducts()
      .then(setProducts)
      .catch(setError)
      .finally(() => setLoading(false))
  }, [])
  
  if (loading) return <Spinner />
  if (error) return <Error message={error.message} />
  return <ProductGrid products={products} />
}

// After
function ProductList() {
  const { data: products, isLoading, error } = useQuery({
    queryKey: ['products'],
    queryFn: api.fetchProducts,
  })
  
  if (isLoading) return <Spinner />
  if (error) return <Error message={error.message} />
  return <ProductGrid products={products} />
}
```

### Converting Context to Jotai

```typescript
// Before
const ThemeContext = createContext<{
  theme: 'light' | 'dark'
  setTheme: (theme: 'light' | 'dark') => void
} | null>(null)

function ThemeProvider({ children }) {
  const [theme, setTheme] = useState<'light' | 'dark'>('light')
  return (
    <ThemeContext.Provider value={{ theme, setTheme }}>
      {children}
    </ThemeContext.Provider>
  )
}

function useTheme() {
  const context = useContext(ThemeContext)
  if (!context) throw new Error('useTheme must be used within ThemeProvider')
  return context
}

// After
export const themeAtom = atomWithStorage<'light' | 'dark'>('theme', 'light')

// No provider needed! Just use:
function Component() {
  const [theme, setTheme] = useAtom(themeAtom)
}
```

---

Quick Reference

### When to Use What

| Need | Use | Example |
|------|-----|---------|
| Page number in URL | Router search params | `?page=2` |
| Fetch user from API | TanStack Query | `useQuery(['user'], fetchUser)` |
| Update user via API | TanStack Query mutation | `useMutation(updateUser)` |
| Login form with validation | React Hook Form | `useForm()` with `zodResolver` |
| Theme toggle (global) | Jotai | `themeAtom` |
| Selected row (shared) | Jotai | `selectedRowIdAtom` |
| Dropdown open (local) | useState | `const [open, setOpen] = useState(false)` |
| Filtered list (local) | useMemo | `useMemo(() => filter(items), [items])` |
| Callback (optimized) | useCallback | `useCallback((id) => {...}, [])` |
| Filter computed from shared data | Jotai derived atom | `atom((get) => filter(get(dataAtom)))` |

### Import Quick Reference

```typescript
// TanStack Router
import { createFileRoute } from '@tanstack/react-router'
import { useNavigate, useParams, useSearch } from '@tanstack/react-router'

// TanStack Query
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'

// Jotai (for shared state)
import { atom, useAtom, useAtomValue, useSetAtom } from 'jotai'
import { atomWithStorage } from 'jotai/utils'
import { splitAtom, selectAtom } from 'jotai/utils'

// React Hooks (for local state)
import { useState, useMemo, useCallback } from 'react'

// React Hook Form
import { useForm, useFieldArray } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
```

### Common Patterns Cheat Sheet

```typescript
// URL state
const { page, filter } = Route.useSearch()
navigate({ search: (prev) => ({ ...prev, page: 2 }) })

// Server state
const { data, isLoading, error } = useQuery({
  queryKey: ['products', filter],
  queryFn: () => api.fetchProducts(filter)
})

// Mutations
const mutation = useMutation({
  mutationFn: api.createProduct,
  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: ['products'] })
  }
})

// Shared client state
const [theme, setTheme] = useAtom(themeAtom)
const value = useAtomValue(readOnlyAtom)
const setValue = useSetAtom(writeOnlyAtom)

// Derived atoms
const derivedAtom = atom((get) => {
  const a = get(atomA)
  const b = get(atomB)
  return a + b
})

// Local state
const [count, setCount] = useState(0)
const doubled = useMemo(() => count * 2, [count])
const handleClick = useCallback(() => {}, [])

// Forms
const { register, handleSubmit, formState: { errors } } = useForm({
  resolver: zodResolver(schema)
})
```

---

Summary

### The Five Layers

1. **TanStack Router** - Routing and URL state
2. **TanStack Query** - All server communication
3. **Jotai** - Shared client-side state across components
4. **React Hooks** - Local component state and computations
5. **React Hook Form** - Complex forms

### Golden Rules

1. **Always ask "What is the source of truth?"** before choosing where to put state
2. **Start local (useState)** and only lift to higher layers when sharing is needed
3. **Use the simplest solution** that works for your use case
4. **Split Jotai atoms granularly** to minimize re-renders
5. **Never duplicate state** across layers

### Source of Truth Mapping

- Source is URL → Router
- Source is server → TanStack Query
- Source is user input (form) → React Hook Form
- Source is client interaction (shared) → Jotai
- Source is client interaction (local) → useState/useMemo/useCallback

By keeping state in the appropriate layer, your application remains maintainable, performant, and easy to reason about.
