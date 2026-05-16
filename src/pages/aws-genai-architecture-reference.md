---
layout: ../layouts/GistLayout.astro
---

# AWS Generative AI Architecture Quick Reference

> Aligned with AWS Certified Generative AI Developer - Professional (AIP-C01) domains.
> Focused on real-world architectural decisions and patterns.

---

## Table of Contents

**[Part 1: Decision Cheat Sheets](#part-1-decision-cheat-sheets)** — Quick-lookup comparison tables and decision trees

Sections flow from data infrastructure → model platforms → intelligent systems → operations:

- [1.1 RAG Architecture Selection](#11-rag-architecture-selection) — which RAG approach for which need
- [1.2 Vector Database Selection](#12-vector-database-selection) — OpenSearch vs. Aurora vs. Neptune vs. managed
- [1.3 k-NN Algorithms & Index Methods](#13-k-nn-algorithms--index-methods-opensearch) — FLAT, HNSW, IVF, engines, parameters
- [1.4 Managing Embeddings at Scale](#14-managing-embeddings-at-scale--size-storage-and-performance) — quantization, Matryoshka, sharding, two-phase search
- [1.5 Foundation Model Selection](#15-foundation-model-selection) — model choice by use case, cascading
- [1.6 Bedrock ↔ SageMaker AI](#16-bedrock--sagemaker-ai--the-interplay) — when which, Custom Model Import, lifecycle
- [1.7 Agent Architecture & Ecosystem](#17-agent-architecture--ecosystem) — Bedrock Agents, Strands, AgentCore, LangChain, CrewAI, MCP
- [1.8 Orchestration](#18-orchestration--step-functions-bedrock-flows-and-chaining-frameworks) — Step Functions, Prompt Flows, LangGraph, EventBridge
- [1.9 Cross-Account & Cross-Region](#19-cross-account--cross-region-bedrock-access-patterns) — inference profiles, multi-account patterns, data residency
- [1.10 Security & Guardrails](#110-security--guardrails-selection) — threats, controls, defense-in-depth
- [1.11 Cost Optimization](#111-cost-optimization-decisions) — caching, batching, cascading, provisioned throughput

**[Part 2: Scenario-Pattern Cards](#part-2-scenario-pattern-cards)** — Real-world architecture scenarios with full service flows

- [Domain 1: FM Integration, Data Management, and Compliance](#domain-1-fm-integration-data-management-and-compliance) (5 cards)
- [Domain 2: Implementation and Integration](#domain-2-implementation-and-integration) (5 cards)
- [Domain 3: AI Safety, Security, and Governance](#domain-3-ai-safety-security-and-governance) (3 cards)
- [Domain 4: Operational Efficiency and Optimization](#domain-4-operational-efficiency-and-optimization) (3 cards)
- [Domain 5: Testing, Validation, and Troubleshooting](#domain-5-testing-validation-and-troubleshooting) (4 cards)

**[Part 3: Condensed Reference by Domain](#part-3-condensed-reference-by-domain)** — Detailed explanations with implementation context

**[Quick Service Reference Card](#quick-service-reference-card)** — One-row-per-capability lookup table

**[Part 4: Documentation Resource List](#part-4-documentation-resource-list)** — 52 curated public AWS documentation links with study order

**[Part 5: From Theory to Practice](#part-5-from-theory-to-practice--specializing-an-llm-for-your-stack)** — How exam concepts translate to real implementation (coding assistant example)

---

## Part 1: Decision Cheat Sheets

### 1.1 RAG Architecture Selection

| Need | Solution | When to Use |
|------|----------|-------------|
| Managed end-to-end RAG | **Bedrock Knowledge Bases** | Default choice; no infra to manage; auto-chunking, embedding, sync |
| Enterprise search + permissions | **Amazon Q Business** | Need per-user ACL, connectors to SaaS (Confluence, SharePoint, Slack) |
| Full control over retrieval pipeline | **Custom RAG** (OpenSearch / Aurora pgvector) | Custom ranking, hybrid search, complex metadata filtering |
| Structured data querying | **Bedrock KB with structured store** | Need natural language → SQL translation |
| Graph-based relationships | **Neptune Analytics** | Entity relationships matter (org charts, supply chains) |

**Decision Flow:**
```
Need RAG?
├─ Unstructured docs + simple setup → Bedrock Knowledge Bases
├─ Enterprise-wide with user permissions → Amazon Q Business
├─ Need hybrid search / custom ranking → Custom (OpenSearch + Bedrock)
├─ Structured DB querying → Bedrock KB (structured data store)
└─ Relationship-heavy data → Neptune Analytics + Bedrock
```

---

### 1.2 Vector Database Selection

| Database | Best For | Key Trade-off |
|----------|----------|---------------|
| **OpenSearch Serverless** | Large-scale, hybrid search (keyword + vector) | Most flexible; higher operational complexity |
| **Aurora PostgreSQL (pgvector)** | Teams already on RDS; moderate scale | Familiar SQL; limited at very high vector dimensions |
| **Bedrock managed store** | Simplest path; integrated with KB | Least control; tied to KB lifecycle |
| **DynamoDB + vector DB** | Metadata-heavy with fast key lookups | Split architecture; good for session/metadata + embeddings |
| **Neptune Analytics** | Graph + vector combined queries | Niche; graph relationships + semantic search |

**Key Sizing Considerations:**
- Embedding dimensions: 256-1536 (Titan: 1024/1536, Cohere: 1024)
- Index type: HNSW for low-latency; IVF for cost-efficiency at scale
- Sharding: OpenSearch auto-shards; Aurora needs partitioning at scale

---

### 1.3 k-NN Algorithms & Index Methods (OpenSearch)

![k-NN Algorithms Compared](/diagrams/02-knn-algorithms.svg)

Vector search in OpenSearch uses k-Nearest Neighbor (k-NN) algorithms to find vectors closest to a query vector. Understanding these algorithms is critical for choosing the right performance/accuracy trade-off.

#### Algorithms Compared

| Algorithm | Type | How It Works | Recall | Search Latency | Memory | Index Build Time |
|-----------|------|--------------|--------|----------------|--------|-----------------|
| **FLAT** | Exact (brute-force) | Compares query against *every* vector in the index. No approximation, no index structure. | 100% (perfect) | High (linear with dataset size) | Low (no extra structures) | None (no index to build) |
| **HNSW** | Approximate (graph-based) | Builds a multi-layer navigable graph. Search starts at top layer (coarse) and descends to bottom layer (fine-grained), following graph edges. | Very high (~95-99%) | Low (logarithmic) | High (graph stored in memory) | Moderate |
| **IVF** | Approximate (partition-based) | Training phase clusters all vectors into `nlist` partitions (Voronoi cells). At query time, identifies `nprobes` nearest partitions and only searches those. | Moderate-high (tunable via nprobes) | Medium | Lower than HNSW | Requires training step |
| **IVFFLAT** | IVF + exact within clusters | Same IVF partitioning, but stores full uncompressed vectors within each cluster. Exact search within selected partitions. | Higher than IVFPQ | Medium | Medium | Requires training |
| **IVFPQ** | IVF + product quantization | IVF partitioning with vectors compressed via Product Quantization (PQ). Vectors are split into sub-vectors, each quantized to a codebook entry. Lossy. | Lower (compression trade-off) | Low | Lowest (highly compressed) | Requires training + codebook |

#### Engines in OpenSearch

| Engine | Algorithms Supported | Best For | Key Details |
|--------|---------------------|----------|-------------|
| **Faiss** (Facebook AI Similarity Search) | HNSW, IVF, IVFFLAT, IVFPQ, FLAT | Most versatile; large-scale production, quantization, training-based indexes | Supports on-disk indexes, GPU acceleration, advanced quantization (SQ, PQ) |
| **nmslib** (Non-Metric Space Library) | HNSW only | Fast HNSW for simple workloads | Lightweight, historically the default, being superseded by Faiss/Lucene |
| **Lucene** | HNSW, FLAT | Combining vector search with traditional filters | Native to OpenSearch; most efficient pre-filtering (filters applied during graph traversal, not after) |

#### Key Parameters

**HNSW parameters (most commonly tuned):**

| Parameter | What It Controls | Default | Higher Value = | Lower Value = |
|-----------|-----------------|---------|----------------|---------------|
| `m` | Bidirectional connections per node | 16 | Better recall, more memory, slower indexing | Less memory, faster indexing, lower recall |
| `ef_construction` | Candidate list size during index build | 512 | Higher quality graph, slower build | Faster build, lower graph quality |
| `ef_search` | Candidate list size at query time | 512 | Better recall, higher latency | Lower latency, lower recall |

**IVF parameters:**

| Parameter | What It Controls | Higher Value = | Lower Value = |
|-----------|-----------------|----------------|---------------|
| `nlist` | Number of partitions (clusters) | Finer granularity, slower training, potentially better precision | Fewer clusters, faster training, coarser search |
| `nprobes` | Partitions searched per query | Better recall (more partitions checked), slower | Faster search, lower recall |

**Space types (distance metrics):**

| Space Type | Use When | Notes |
|-----------|----------|-------|
| `l2` (Euclidean) | Default; general purpose | Measures straight-line distance between points |
| `cosinesimil` (Cosine similarity) | Text embeddings, normalized vectors | Measures angle between vectors; magnitude-independent |
| `innerproduct` (Dot product) | When vectors are pre-normalized | Fastest computation; equivalent to cosine on normalized vectors |

#### Algorithm Selection Decision Tree

```
Which k-NN algorithm?
├─ Need 100% accuracy (exact results)?
│   ├─ Small dataset (<100K vectors) → FLAT (brute force, no tuning)
│   └─ Large dataset but exact needed → FLAT with Lucene engine (supports pre-filtering)
│
├─ Need high recall + low latency (most RAG use cases)?
│   → HNSW (default choice)
│   ├─ Need efficient filtering? → Lucene engine (filter during traversal)
│   ├─ Need max flexibility? → Faiss engine (quantization options)
│   └─ Simple setup? → nmslib engine (HNSW only, lightweight)
│
├─ Very large dataset (billions) + memory constrained?
│   → IVF family (Faiss engine only)
│   ├─ Can afford memory for full vectors? → IVFFLAT (better recall)
│   └─ Need smallest memory footprint? → IVFPQ (lossy compression, smallest)
│
└─ Combining vector + keyword/metadata filtering?
    → Lucene engine + HNSW (pre-filtering during graph traversal)
```

#### Configuration Example (HNSW with Faiss)

```json
PUT /my-vector-index
{
  "settings": {
    "index": { "knn": true }
  },
  "mappings": {
    "properties": {
      "embedding": {
        "type": "knn_vector",
        "dimension": 1024,
        "method": {
          "name": "hnsw",
          "space_type": "cosinesimil",
          "engine": "faiss",
          "parameters": {
            "m": 16,
            "ef_construction": 256,
            "ef_search": 256
          }
        }
      }
    }
  }
}
```

#### Key Exam Signals

| Signal in Question | Answer Points To |
|--------------------|-----------------|
| "100% accuracy" or "exact match" | FLAT |
| "low latency" + "high recall" | HNSW |
| "memory constrained" + "billions of vectors" | IVF / IVFPQ |
| "combine with keyword filters" | Lucene engine |
| "training step required" | IVF family (not HNSW — HNSW doesn't need training) |
| "product quantization" or "compressed vectors" | IVFPQ |
| "graph-based" | HNSW |
| "partition-based" or "cluster-based" | IVF |

#### Documentation References

| Resource | URL |
|----------|-----|
| k-NN in AWS OpenSearch Service | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/knn.html |
| OpenSearch Methods & Engines | https://docs.opensearch.org/latest/mappings/supported-field-types/knn-methods-engines/ |
| OpenSearch Approximate k-NN | https://docs.opensearch.org/latest/vector-search/vector-search-techniques/approximate-knn/ |
| Choosing a vector DB for RAG (AWS) | https://docs.aws.amazon.com/prescriptive-guidance/latest/choosing-an-aws-vector-database-for-rag-use-cases/introduction.html |

---

### 1.4 Managing Embeddings at Scale — Size, Storage, and Performance

![Embedding Optimization Techniques](/diagrams/12-embedding-optimization.svg)

As vector stores grow to millions or billions of embeddings, the raw size of vectors becomes a bottleneck for memory, storage, and search latency. Several techniques exist to reduce embedding size while preserving search quality.

#### The Problem

A typical RAG system with 10M documents at 1024 dimensions (float32):
```
10,000,000 vectors × 1024 dimensions × 4 bytes = ~40 GB

That's 40 GB just for embeddings (before metadata, indexes, replicas).
At 100M docs → 400 GB. Memory-resident indexes become expensive.
```

#### Techniques for Reducing Embedding Size

| Technique | How It Works | Size Reduction | Recall Impact | When to Use |
|-----------|--------------|----------------|---------------|-------------|
| **Dimensionality reduction (native)** | Model outputs fewer dimensions (e.g., Titan V2: 256 vs. 1024) | 4x (1024→256) | Minor (5-10% drop) | First thing to try; cheapest approach |
| **Matryoshka embeddings** | Model trained so first N dimensions are independently useful. Truncate to any prefix length. | Variable (truncate to any N) | Graceful degradation | When model supports it (newer Cohere, some OSS models) |
| **Scalar quantization (SQ)** | Convert float32 → int8 per dimension | 4x | Minimal (<2% recall loss) | Default recommendation for production at scale |
| **Binary quantization (BQ)** | Convert each dimension to single bit (>0 = 1, ≤0 = 0) | 32x | Moderate (5-15% loss) | Massive scale, coarse first-pass retrieval + reranker |
| **Product quantization (PQ)** | Split vector into sub-vectors, quantize each to codebook entry | 8-32x | Moderate (tunable) | IVF indexes (IVFPQ in Faiss/OpenSearch) |
| **Dimension truncation (post-hoc)** | Simply drop trailing dimensions from any embedding | Variable | Unpredictable (depends on model) | Only with Matryoshka-trained models; otherwise DO NOT use |
| **Multi-vector (ColBERT-style)** | One vector per token instead of one per document. More vectors but each smaller. | Size increases but precision improves | Better recall | Precision-critical, latency-tolerant use cases |

#### Technique Deep Dives

**Native Dimensionality Selection (simplest):**

Amazon Titan Embeddings V2 supports configurable output dimensions at inference time:
```
# Titan V2 — choose at embed time (no retraining)
dimensions: 256  → fastest search, smallest storage, slight recall loss
dimensions: 512  → balanced (recommended sweet spot for most RAG)
dimensions: 1024 → highest recall, largest storage
```
This is a model-level choice — you pick dimensions when generating embeddings. All documents AND queries must use the same dimension. Changing requires full re-embedding.

**Matryoshka Embeddings (nested dolls):**

Named after Russian nesting dolls. The model is trained so that the first N dimensions carry the most important information, and each additional dimension adds refinement.

```
Full embedding:    [d1, d2, d3, d4, ......, d1024]
                    ├── most important ──────── least important ──┤

Truncate to 256:   [d1, d2, d3, ..., d256]  ← still meaningful!
Truncate to 512:   [d1, d2, ..., d512]       ← better quality
Full 1024:         [d1, d2, ..., d1024]      ← best quality
```

**Key insight:** unlike arbitrary truncation, Matryoshka embeddings are *trained* for this — the information is front-loaded. You can:
- Index at full 1024 dimensions
- Do coarse search at 256 dimensions (fast)
- Rerank candidates at 1024 dimensions (accurate)

**Scalar Quantization (SQ) — float32 → int8:**

Each float32 value (4 bytes) mapped to int8 (1 byte). Per-dimension scaling preserves relative distances.

```
Original:   [0.234, -0.891, 0.045, ...]  (float32 × 1024 = 4096 bytes)
Quantized:  [60, -228, 11, ...]           (int8 × 1024 = 1024 bytes)
Savings:    4x storage reduction
```

OpenSearch supports this natively with `data_type: byte` in k-NN field mappings:
```json
{
  "my_vector": {
    "type": "knn_vector",
    "dimension": 1024,
    "data_type": "byte",
    "method": {
      "name": "hnsw",
      "engine": "lucene"
    }
  }
}
```

**Binary Quantization (BQ) — float32 → 1 bit:**

Each dimension becomes a single bit: positive → 1, negative → 0.

```
Original:   [0.234, -0.891, 0.045, -0.567, ...]  (4096 bytes for 1024d)
Binary:     [1, 0, 1, 0, ...]                      (128 bytes for 1024d!)
Savings:    32x storage reduction
```

Distance computed via Hamming distance (XOR + popcount) — extremely fast on hardware.

**Trade-off:** significant recall loss (~10-15%). Best used as a **first-pass filter**:
```
Query → Binary search (32x faster, top-1000) → Rerank with full vectors (top-10)
```

**Product Quantization (PQ):**

Splits the vector into M sub-vectors, each quantized independently via a learned codebook.

```
Original vector (1024d):
  [sub-vector 1 (128d)] [sub-vector 2 (128d)] ... [sub-vector 8 (128d)]
        ↓                      ↓                          ↓
  codebook entry: 42      entry: 187                 entry: 5
  (1 byte each)           (1 byte)                   (1 byte)

Compressed: [42, 187, ..., 5] = 8 bytes (from 4096 bytes!)
```

Used in OpenSearch/Faiss as **IVFPQ** (partition + compress). Requires a training step to build codebooks.

#### Horizontal Scaling Patterns (when data doesn't fit in one index)

| Pattern | How It Works | When to Use |
|---------|--------------|-------------|
| **Sharding** (OpenSearch native) | Distribute index across multiple shards on different nodes | Default for large indexes; OpenSearch handles automatically |
| **Multi-index by domain** | Separate indexes per content domain (HR docs, engineering docs, legal) | Different domains need different settings (chunk sizes, scoring weights) |
| **Multi-index by time** | Separate indexes per time period (monthly/quarterly) | Time-decay relevance; archive old indexes to warm/cold storage |
| **Tiered storage** | Hot (memory) → Warm (disk-backed) → Cold (S3-based) | Cost optimization; old vectors rarely searched |
| **Filtered subsets** | Single index with metadata filters to narrow search scope | Pre-filter by department/tenant/date before vector search |

**OpenSearch sharding for embeddings:**
```
Index with 100M vectors at 1024d (float32):
  Total data: ~400 GB

Sharding strategy:
  - 20 shards × 5 GB each (primary)
  - 1 replica = 40 shards total (800 GB across cluster)
  - Nodes: 10 nodes × 80 GB RAM each
  - Each node holds 4 shards in memory

Search: query hits all 20 primary shards in parallel → merge results
```

**Multi-index architecture for RAG:**
```
┌─────────────────────────────────────────────────────┐
│ Query Router                                        │
│  └─ Classifies query → routes to relevant index(es) │
├─────────────┬──────────────┬────────────────────────┤
│ HR Index    │ Eng Index    │ Legal Index            │
│ 512d, HNSW  │ 1024d, HNSW  │ 768d, HNSW             │
│ cosine      │ cosine       │ cosine                 │
│ 50K docs    │ 2M docs      │ 500K docs              │
│ chunk: 256  │ chunk: 512   │ chunk: 1024 (contracts)│
└─────────────┴──────────────┴────────────────────────┘
Each index optimized for its content type.
```

#### Two-Phase Search (combining techniques)

The most cost-effective pattern at scale combines cheap coarse search with accurate reranking:

```
Phase 1: FAST (coarse)
  • Binary quantized or low-dimension Matryoshka embeddings
  • Retrieve top-1000 candidates very quickly
  • Low memory, high throughput

Phase 2: ACCURATE (rerank)
  • Full-precision vectors OR cross-encoder reranker model
  • Re-score the 1000 candidates
  • Return top-5 to FM
```

This gives you near-FLAT recall at near-HNSW latency, with the storage costs of quantized vectors.

#### Decision Guide: Embedding Size Optimization

```
Starting point: too much memory / storage / latency?
│
├─ Can you reduce dimensions at model level?
│   ├─ Using Titan V2? → Try 512d instead of 1024d (no re-training)
│   └─ Model supports Matryoshka? → Truncate to first N dimensions
│
├─ Still too large? Apply quantization:
│   ├─ Want minimal recall loss? → Scalar quantization (int8, 4x savings)
│   ├─ Need extreme compression? → Binary quantization (32x) + reranker
│   └─ Using IVF index? → Product quantization (IVFPQ, 8-32x)
│
├─ Data volume exceeds single node?
│   ├─ Uniform content → OpenSearch sharding (automatic)
│   ├─ Distinct domains → Multi-index by domain (separate optimization)
│   └─ Time-sensitive → Multi-index by time + tiered storage
│
└─ Need both speed AND accuracy at scale?
    → Two-phase: coarse (binary/low-d) → rerank (full precision)
```

#### AWS Service Mapping

| Technique | Supported In | Configuration |
|-----------|--------------|---------------|
| Native dimension selection | Titan V2 (256/512/1024), Cohere (configurable) | Set at embedding time |
| Scalar quantization (byte) | OpenSearch (Lucene engine), Aurora pgvector | `data_type: byte` in mapping |
| Binary quantization | OpenSearch (Faiss engine) | Faiss encoder configuration |
| Product quantization | OpenSearch (Faiss IVFPQ) | `method.name: ivfpq` + encoder params |
| Sharding | OpenSearch (automatic) | `number_of_shards` in index settings |
| Tiered storage | OpenSearch (hot/warm/cold) | UltraWarm + cold storage tier |
| Multi-index | OpenSearch, Aurora (multiple tables) | Application-level routing |
| Two-phase (rerank) | Bedrock reranker + OpenSearch | Retrieve large k → rerank → top-n |

#### Key Exam Signals

| Signal in Question | Answer Points To |
|--------------------|-----------------|
| "Reduce embedding storage" + "minimal recall loss" | Scalar quantization (int8) |
| "32x compression" or "Hamming distance" | Binary quantization |
| "First N dimensions meaningful" or "nested" | Matryoshka embeddings |
| "Codebook" or "sub-vectors" | Product quantization |
| "Configure output dimensions" (Titan) | Native dimensionality selection |
| "Archive old embeddings" or "cost" | Tiered storage (warm/cold) |
| "Separate index per domain" | Multi-index architecture |
| "Fast first pass + accurate second pass" | Two-phase (binary → rerank) |
| "Embedding size at inference time" | Model supports configurable dimensions |
| "Full re-index required" | Changing embedding model or dimensions |

---

### 1.5 Foundation Model Selection

| Scenario | Model Choice | Rationale |
|----------|--------------|-----------|
| General chat, reasoning | Claude (Anthropic) / Nova Pro | Strong reasoning, long context |
| Cost-sensitive high-volume | Nova Lite / Nova Micro | Lower cost per token, adequate quality |
| Code generation | Claude / Amazon Q Developer | Code understanding + generation |
| Embeddings | Titan Embeddings V2 | Native AWS, good dimension options |
| Image generation | Titan Image / Stability AI | Titan for enterprise; Stability for creative |
| Multimodal understanding | Claude / Nova | Image+text input support |
| Reranking retrieved results | Bedrock reranker models | Improve RAG precision without changing retrieval |

**Model Cascading Pattern:**
```
User Query → Complexity Classifier (small model / rules)
├─ Simple → Nova Micro (cheapest)
├─ Medium → Nova Pro (balanced)
└─ Complex → Claude Opus (highest quality)
```

---

### 1.6 Bedrock ↔ SageMaker AI — The Interplay

![Bedrock and SageMaker Interplay](/diagrams/10-bedrock-sagemaker.svg)

Bedrock and SageMaker AI are **complementary, not competing**. Bedrock is for consuming/customizing foundation models via API. SageMaker is for building, training, and hosting models you fully control. Many production architectures use both.

#### The Mental Model

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        YOUR APPLICATION                                  │
│                              │                                           │
│              ┌───────────────┴───────────────┐                           │
│              ▼                               ▼                           │
│  ┌───────────────────────┐      ┌───────────────────────────┐            │
│  │   Amazon Bedrock      │      │   Amazon SageMaker AI     │            │
│  │                       │      │                           │            │
│  │ • Managed FM access   │      │ • Train custom models     │            │
│  │ • Converse/Invoke API │      │ • Host any model (GPU)    │            │
│  │ • Knowledge Bases     │      │ • Full ML lifecycle       │            │
│  │ • Agents / AgentCore  │      │ • Custom containers       │            │
│  │ • Guardrails          │      │ • Model Monitor / Clarify │            │
│  │ • Prompt Management   │      │ • Notebooks / Experiments │            │
│  │ • Model Evaluation    │      │ • Model Registry          │            │
│  │ • Custom Model Import │◄─────│ • Training jobs           │            │
│  │   (bring model IN)    │      │ • JumpStart (model zoo)   │            │
│  └───────────────────────┘      └───────────────────────────┘            │
│         │                                    │                           │
│         │  Serverless, unified API           │  Full control, any model  │
│         │  No infra management               │  Manage instances/scaling │
└─────────┴────────────────────────────────────┴───────────────────────────┘
```

#### When to Use Which

| Scenario | Service | Why |
|----------|---------|-----|
| Access Claude, Llama, Nova, Titan, Mistral via API | **Bedrock** | Serverless, unified API, no infra |
| Build RAG with managed chunking/embedding/retrieval | **Bedrock** (Knowledge Bases) | Fully managed pipeline |
| Fine-tune a Bedrock-supported model with your data | **Bedrock** (Custom Models) | Fine-tune within Bedrock, deploy within Bedrock |
| Continued pre-training on domain corpus | **Bedrock** (Custom Models) | Stays in Bedrock ecosystem |
| Train a model from scratch on your data | **SageMaker** | Bedrock doesn't train from scratch |
| Host a Hugging Face model not available in Bedrock | **SageMaker** endpoints | Custom container + GPU selection |
| Host a Hugging Face model AND want Bedrock unified API | **Custom Model Import** (Bedrock) | Import into Bedrock, get Converse API access |
| Need specific GPU types (p5, trn1) | **SageMaker** | Bedrock abstracts hardware; SageMaker exposes it |
| Custom pre/post-processing around inference | **SageMaker** (inference pipeline) | Full container control |
| Bias detection / explainability | **SageMaker Clarify** | Works for both SageMaker and Bedrock models |
| Model drift monitoring | **SageMaker Model Monitor** | Custom metrics, NLP-specific drift detection |
| Version models with approval gates | **SageMaker Model Registry** | CI/CD integration, stage transitions |
| Labeling training data | **SageMaker Ground Truth** | Human annotation workflows |
| Quick prototype with pre-trained FM | **Bedrock** | Instant access, no deployment needed |
| A/B test between model versions in production | **SageMaker** (shadow testing, variants) | Built-in traffic splitting |

#### Custom Model Import — Bringing Models INTO Bedrock

This is the bridge: train/fine-tune anywhere → import into Bedrock → get unified API access (Converse, InvokeModel, Guardrails, Agents).

**What it supports:**
- Models from Hugging Face Hub
- Models trained in SageMaker
- Models from any source in supported formats

**Supported formats:**
| Format | Description |
|--------|-------------|
| **Safetensors** | Hugging Face's safe, fast format. Preferred. |
| **GGUF** | Quantized format (llama.cpp). For smaller/quantized models. |

**Import workflow:**
```
1. Train or download model
   └─ SageMaker training job, Hugging Face Hub, or custom training

2. Store model artifacts in S3
   └─ Weights (safetensors/GGUF) + tokenizer + config

3. Create import job in Bedrock
   └─ Specify S3 path, model architecture, compute requirements

4. Bedrock validates + optimizes model
   └─ Checks compatibility, sets up serving infrastructure

5. Model available via Bedrock APIs
   └─ Converse API, InvokeModel, attach to Agents/KB/Guardrails
   └─ Requires Provisioned Throughput (no on-demand for imported models)
```

**Key constraints:**
- Imported models require **Provisioned Throughput** — no on-demand pricing
- Must be a **supported architecture** (decoder-only transformers: Llama, Mistral, etc.)
- **No Bedrock-specific fine-tuning** after import — fine-tune before importing
- Imported models **can** use Guardrails, Agents, Knowledge Bases once imported

**When to import vs. keep on SageMaker endpoint:**

| Keep on SageMaker | Import to Bedrock |
|-------------------|-------------------|
| Need specific GPU/instance types | Want unified Bedrock API (Converse) |
| Custom inference code (pre/post-processing) | Want to use with Bedrock Agents |
| Need auto-scaling to zero (Serverless endpoints) | Want Guardrails applied |
| Model architecture not supported by import | Want Prompt Management integration |
| Temporary/experimental deployment | Production long-term deployment |
| Need real-time A/B testing variants | Want consistent API across all models |

#### Bedrock Model Customization (within Bedrock)

These operations happen entirely within Bedrock — no SageMaker needed:

| Method | Input | What Changes | Output | Use When |
|--------|-------|--------------|--------|----------|
| **Continued Pre-Training** | Raw unlabeled text (domain corpus) | Model's knowledge base expands | Custom model (new weights) | "Understand medical terminology" |
| **Fine-Tuning** | Labeled pairs (JSONL: prompt → completion) | Model's behavior/style changes | Custom model (new weights) | "Always respond in our brand voice" |
| **Distillation** (Bedrock) | Teacher model + unlabeled data | Small model learns from large model | Smaller custom model | "Make Nova Micro behave like Claude for our use case" |

**After customization:**
- Custom model gets a unique model ID
- Deploy with **Provisioned Throughput** (required for custom models)
- Version via the custom model ARN
- Can attach Guardrails, use with Agents/KB
- Cannot further customize an already-customized model (chain = train new)

**Training data requirements:**
- Format: **JSONL** (one JSON object per line)
- Bedrock fine-tuning: `{"prompt": "...", "completion": "..."}` or Converse format
- Continued pre-training: `{"input": "raw text block"}`
- Min/max dataset sizes vary by base model (check docs)
- Data stored in S3, Bedrock reads it during training job

#### SageMaker Features That Complement Bedrock

Even if your inference runs on Bedrock, these SageMaker capabilities add value:

| SageMaker Feature | How It Complements Bedrock | Example |
|-------------------|---------------------------|---------|
| **Model Registry** | Version custom models before importing to Bedrock. Track lineage, approval gates, stage transitions (dev→staging→prod). | Register fine-tuned model → approve → import to Bedrock |
| **Clarify** | Evaluate Bedrock model outputs for bias across demographics. Runs post-hoc on saved outputs. | Weekly bias audit on Bedrock chatbot responses |
| **Model Monitor** | Detect drift in embedding quality or FM output distributions. Custom ECR container for NLP-specific metrics. | Alert when RAG retrieval quality degrades |
| **Ground Truth** | Create labeled datasets for Bedrock fine-tuning. Human annotation with quality controls. | Label 10K examples for fine-tuning job |
| **Data Wrangler** | Prepare/clean data before feeding to Bedrock KB or fine-tuning. Visual transforms. | Clean messy PDFs → structured text for KB ingestion |
| **Processing Jobs** | Run batch data transforms at scale (serverless). | Process 1M documents for RAG ingestion |
| **Experiments** | Track and compare Bedrock fine-tuning runs with different hyperparameters. | Compare 5 fine-tuning configs, pick best |
| **JumpStart** | Access models not yet in Bedrock. Quick deploy to SageMaker endpoint. | Deploy a new model day-of-release before Bedrock supports it |

#### SageMaker JumpStart vs. Bedrock — Model Access

Both offer access to foundation models, but differently:

| Dimension | Bedrock | SageMaker JumpStart |
|-----------|---------|---------------------|
| **Access model** | API call (serverless) | Deploy to endpoint (instance-based) |
| **You manage** | Nothing (serverless) | Instance type, scaling, endpoint lifecycle |
| **Model catalog** | Curated (Anthropic, Meta, Mistral, Amazon, Cohere, etc.) | Broader (Hugging Face Hub + curated) |
| **Customization** | Fine-tune + continued pre-training (in Bedrock) | Full training/fine-tuning (SageMaker) |
| **Pricing** | Per-token (on-demand) or provisioned throughput | Per-hour (instance) |
| **Integrated features** | Agents, KB, Guardrails, Prompt Mgmt, Evaluation | Model Monitor, Clarify, A/B testing |
| **Day-1 new models** | When Bedrock adds support | Often available same day via HF Hub |
| **When to use** | Production apps needing managed FM access | Experimentation, specific models, full control |

#### End-to-End Model Lifecycle (Both Services)

```
EXPERIMENT (SageMaker)
  │ Notebooks → try models from JumpStart
  │ Compare via Experiments
  │
  ▼
TRAIN / FINE-TUNE
  ├─ Simple customization → Bedrock Custom Models (fine-tune/CPT)
  └─ Complex training → SageMaker Training Jobs
       │ Custom algorithms, distributed training, specific GPUs
       │
       ▼
REGISTER (SageMaker Model Registry)
  │ Version model, attach metadata, approval workflow
  │ Lineage tracking (what data, what hyperparameters)
  │
  ▼
DEPLOY
  ├─ Want Bedrock ecosystem? → Custom Model Import
  │    Provisioned Throughput → Converse API, Agents, Guardrails
  │
  └─ Need full control? → SageMaker Endpoint
       Real-time, Serverless, or Async
       Custom containers, A/B variants
       │
       ▼
MONITOR
  ├─ Bedrock: Invocation logs, CloudWatch metrics, Model Evaluation
  └─ SageMaker: Model Monitor (drift), Clarify (bias), Data Capture
       │
       ▼
ITERATE
  └─ Evaluation results inform next training cycle
```

#### Key Exam Signals

| Signal in Question | Answer Points To |
|--------------------|-----------------|
| "Serverless FM access" + "no infrastructure" | Bedrock |
| "Custom training from scratch" | SageMaker Training |
| "Hugging Face model" + "Bedrock API access" | Custom Model Import |
| "Version models with approval gates" | SageMaker Model Registry |
| "Detect bias in FM outputs" | SageMaker Clarify |
| "Monitor embedding drift" | SageMaker Model Monitor + custom ECR |
| "Fine-tune with labeled data" + "deploy to Bedrock" | Bedrock Custom Models (stays in Bedrock) |
| "Specific GPU type" or "p5 instances" | SageMaker endpoints |
| "A/B test model versions" or "shadow testing" | SageMaker (built-in variants) |
| "Label training data" | SageMaker Ground Truth |
| "JSONL dataset" + "fine-tuning" | Bedrock Custom Models |
| "Safetensors" or "GGUF" + "import" | Custom Model Import |
| "Provisioned throughput required" | Custom Model Import OR Bedrock custom models |
| "Scale to zero" + "variable traffic" | SageMaker Serverless endpoints (NOT Bedrock — Bedrock on-demand doesn't scale to zero, it's pay-per-token) |

---
### 1.7 Agent Architecture & Ecosystem

#### Quick Selection

| Pattern | Implementation | When to Use |
|---------|---------------|-------------|
| Simple tool-calling agent | **Bedrock Agents** (action groups) | Single agent, defined APIs, managed orchestration |
| Multi-agent collaboration | **Bedrock AgentCore** / Strands + Agent Squad | Specialized agents working together |
| Event-driven agent workflows | **Step Functions + Lambda + Bedrock** | Complex async workflows, human-in-the-loop |
| Lightweight tool access | **MCP servers on Lambda** | Stateless tool integrations, standardized protocol |
| Stateful long-running agents | **MCP servers on ECS** | Need persistent connections, complex tools |
| Custom orchestration | **Strands Agents SDK** | Full control, custom ReAct/planning loops |

**Agent Safety Controls:**
```
Agent Execution
├─ IAM least-privilege (resource boundaries)
├─ Step Functions timeout + circuit breaker
├─ Guardrails on input/output
├─ Human approval gates (Step Functions callback)
└─ CloudWatch alarms on token/cost spikes
```

#### The Full Picture

![Agent Ecosystem — Layered Architecture](/diagrams/08-agent-ecosystem.svg)

The AWS agent landscape is layered. Understanding which layer each tool operates at is key to choosing the right combination.

#### The Agent Stack (layered architecture)

```
┌─────────────────────────────────────────────────────────────────────┐
│ FRAMEWORKS (how you build agent logic)                              │
│                                                                     │
│  AWS-Native:                        Open Source:                    │
│  ┌─────────────────┐ ┌───────────┐  ┌──────────┐ ┌──────────────┐   │
│  │ Bedrock Agents  │ │ Strands   │  │LangGraph │ │ CrewAI       │   │
│  │ (managed,       │ │ Agents    │  │(stateful │ │ (role-based  │   │
│  │  no-code)       │ │ (SDK,     │  │ graphs)  │ │  multi-agent)│   │
│  └─────────────────┘ │  code)    │  └──────────┘ └──────────────┘   │
│                      └───────────┘  ┌──────────┐ ┌──────────────┐   │
│  ┌─────────────────┐                │AutoGen   │ │ LangChain    │   │
│  │ Agent Squad     │                │(MS,      │ │ (chains +    │   │
│  │ (multi-agent    │                │ conv.)   │ │  agents)     │   │
│  │  supervisor)    │                └──────────┘ └──────────────┘   │
│  └─────────────────┘                                                │
├─────────────────────────────────────────────────────────────────────┤
│ RUNTIME (where agents execute)                                      │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │ Amazon Bedrock AgentCore Runtime                         │       │
│  │ (managed hosting, auto-scaling, identity, observability) │       │
│  └──────────────────────────────────────────────────────────┘       │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌─────────────┐    │
│  │ Lambda     │  │ ECS/Fargate│  │ EC2        │  │ Step Funcs  │    │
│  │(stateless) │  │ (stateful) │  │ (full ctrl)│  │(orchestrate)│    │
│  └────────────┘  └────────────┘  └────────────┘  └─────────────┘    │
├─────────────────────────────────────────────────────────────────────┤
│ PROTOCOLS & TOOLS (how agents access external capabilities)         │
│                                                                     │
│  ┌───────────────────────────────────┐  ┌─────────────────────────┐ │
│  │ MCP (Model Context Protocol)      │  │ Function Calling        │ │
│  │ (standardized tool interface,     │  │ (model-native,          │ │
│  │  reusable across frameworks)      │  │  JSON structured output)│ │
│  └───────────────────────────────────┘  └─────────────────────────┘ │
│  ┌───────────────────────────────────┐  ┌─────────────────────────┐ │
│  │ OpenAPI Schemas                   │  │ AgentCore Connectors    │ │
│  │ (Bedrock Agents action groups)    │  │ (prebuilt integrations) │ │
│  └───────────────────────────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

#### Framework Decision Matrix

| Framework | Type | Orchestration | Multi-Agent | MCP Support | Deployment | Best For |
|-----------|------|---------------|-------------|-------------|------------|----------|
| **Bedrock Agents** | AWS managed | Automatic (ReAct) | Via Agent Squad | Via AgentCore | Serverless (managed) | Simple agents, no code, fast to production |
| **Strands Agents** | AWS open-source SDK | Custom (any pattern) | Built-in | Native | Lambda, ECS, AgentCore | Production agents needing full code control |
| **Agent Squad** | AWS multi-agent | Supervisor + routing | Core purpose | Via Strands | Lambda, ECS, AgentCore | Coordinated specialist agents |
| **LangChain** | OSS (Python/JS) | Chains + agents | Via LangGraph | Community adapters | Self-managed | Maximum ecosystem, any LLM provider |
| **LangGraph** | OSS (LangChain ext) | Stateful graph | Native (graph nodes) | Community | Self-managed | Complex stateful workflows, cycles, branching |
| **CrewAI** | OSS (Python) | Role-based | Core purpose | Limited | Self-managed | Role-playing multi-agent, sequential tasks |
| **AutoGen** | OSS (Microsoft) | Conversational | Core purpose | Limited | Self-managed | Conversational multi-agent, research workflows |

#### How They Relate (not alternatives — layers)

```
Scenario: Production multi-agent system on AWS

Framework:   Strands Agents (write agent logic in Python)
               + Agent Squad (coordinate multiple agents)
Runtime:     AgentCore (hosts agents, provides memory, scales)
Tools:       MCP servers (standardized tool access)
Safety:      Bedrock Guardrails (applied at AgentCore level)
```

```
Scenario: Quick single-agent PoC

Framework:   Bedrock Agents (no code, console-based)
Runtime:     Managed by Bedrock (serverless)
Tools:       Action Groups (OpenAPI + Lambda)
Safety:      Guardrails (attached to agent)
```

```
Scenario: OSS flexibility + AWS infrastructure

Framework:   LangGraph (stateful agent graph)
Runtime:     ECS Fargate (self-managed containers)
Tools:       MCP servers on Lambda (reusable across frameworks)
Safety:      Custom (Comprehend + Lambda pre/post processing)
```

#### Bedrock AgentCore — Platform Deep Dive

AgentCore isn't a framework — it's the **runtime platform** that hosts agents built with any framework.

| Feature | What It Does | Why It Matters |
|---------|--------------|----------------|
| **AgentCore Runtime** | Hosts agent code as HTTP service (`/invocations`, `/ping`). Auto-scales, manages containers. | Deploy agents without managing infra. One command via starter toolkit. |
| **Memory (short-term)** | Maintains conversation context within a session | Multi-turn conversations without custom state management |
| **Memory (long-term)** | Persists user preferences, decisions, patterns across sessions | Agent "remembers" you — personalization without re-prompting |
| **Identity Propagation** | Built-in OIDC support (Microsoft Entra ID). Passes user identity to tools. | Agent actions respect per-user permissions. No custom auth plumbing. |
| **Prebuilt MCP Servers** | Ready-to-use connectors for Aurora, S3, common services | Zero custom code for standard data access |
| **Observability** | Built-in tracing, metrics, invocation logging | Debug agent reasoning without custom instrumentation |
| **`@app.entrypoint` decorator** | Auto-creates HTTP server on port 8080 with correct endpoints | Write agent logic only — decorator handles infrastructure |
| **Starter Toolkit** | Automated packaging → containerization → ECR push → deploy | Focus on agent logic, not DevOps |

**When to use AgentCore vs. self-managed:**

| Factor | AgentCore | Self-Managed (Lambda/ECS) |
|--------|-----------|---------------------------|
| Scaling | Automatic | Configure auto-scaling yourself |
| Memory | Built-in short + long term | Build with DynamoDB / Redis |
| Identity | Native OIDC | Cognito + custom Lambda authorizer |
| Observability | Built-in traces | X-Ray + custom instrumentation |
| Framework lock-in | Any framework (Strands, LangChain, etc.) | Any framework |
| Cost | Managed service pricing | Pay for compute directly |
| Control | Less (managed) | Full |

#### Agent Orchestration Patterns

| Pattern | How It Works | When to Use | Implementation |
|---------|--------------|-------------|----------------|
| **ReAct** (Reasoning + Acting) | Observe → Reason → Act → Observe → ... loop | Most common; structured problem-solving | Bedrock Agents (built-in), Strands (custom) |
| **Plan-and-Execute** | Generate full plan first, then execute steps sequentially | Known multi-step tasks; predictable workflows | Strands Agents, LangGraph |
| **Tool-Use** | Model decides which tool to call based on query | Single-step tool interactions | Any framework (function calling) |
| **Reflexion** | Agent evaluates its own output, retries if quality is low | Self-improving responses; quality-critical tasks | Custom (Strands + evaluation loop) |
| **Supervisor + Workers** | Supervisor routes to specialized sub-agents | Complex tasks needing multiple domains | Agent Squad, CrewAI |
| **Hierarchical** | Multiple supervisor layers (manager → team leads → workers) | Large-scale, organization-like structure | Agent Squad (nested), LangGraph |
| **Consensus / Debate** | Multiple agents argue/vote on an answer | High-stakes decisions needing diverse perspectives | Custom (Strands multi-agent) |

#### Agent Memory: When to Use What

| Memory Type | Stored Where | Lifetime | Use For | Service |
|-------------|--------------|----------|---------|---------|
| **Conversation context** (short-term) | In-memory / AgentCore | Single session | Multi-turn chat, follow-up questions | AgentCore Memory, DynamoDB |
| **Long-term memory** | AgentCore persistent store | Cross-session | User preferences, past decisions, behavioral patterns | AgentCore Memory |
| **RAG (knowledge)** | Vector store | Persistent (synced) | Factual knowledge, documentation, policies | Bedrock Knowledge Bases |
| **Tool state** | External systems | Varies | Current bookings, account status, live data | Agent tools / APIs |

**Key distinction:** Long-term memory answers "who is this user and what happened before." RAG answers "what do authoritative sources say right now." Use both together for personalized + accurate responses.

#### Decision Flow: Choosing Your Agent Stack

```
What are you building?
│
├─ Single-purpose agent, quick to production?
│   → Bedrock Agents (managed, no code)
│   → Add Guardrails + Knowledge Base
│   → Done.
│
├─ Production multi-agent, need code control?
│   ├─ Want AWS-native + open-source?
│   │   → Strands Agents + Agent Squad
│   │   → Deploy on AgentCore (managed runtime)
│   │   → MCP for tools
│   │
│   └─ Want maximum ecosystem / provider flexibility?
│       → LangGraph (stateful) or LangChain (simple)
│       → Deploy on ECS Fargate
│       → MCP for tool reuse
│
├─ Need human approval in the loop?
│   → Step Functions (callback pattern) + any framework
│
├─ Existing LangChain/CrewAI codebase?
│   → Keep framework, deploy on AgentCore or ECS
│   → Add MCP servers for tool standardization
│   → Wrap with Bedrock Guardrails via ApplyGuardrail API
│
└─ Edge case: conversational multi-agent research?
    → AutoGen (Microsoft) for debate/consensus patterns
    → Deploy on ECS (needs persistent connections)
```

#### Open Source vs. AWS-Native Trade-offs

| Dimension | AWS-Native (Bedrock/Strands/AgentCore) | Open Source (LangChain/LangGraph/CrewAI) |
|-----------|----------------------------------------|------------------------------------------|
| **Time to production** | Faster (managed infra, less glue code) | Slower (more setup, self-managed) |
| **LLM provider flexibility** | Bedrock models (many providers via API) | Any provider (OpenAI, Anthropic, local, etc.) |
| **Lock-in risk** | AWS services | Framework community (may change direction) |
| **Enterprise features** | Built-in (IAM, logging, guardrails) | Build yourself or use paid tiers (LangSmith, etc.) |
| **Community / examples** | Smaller but growing | Large ecosystem, many tutorials |
| **Multi-agent support** | Agent Squad + AgentCore | LangGraph, CrewAI, AutoGen (more mature) |
| **MCP support** | Native in Strands + AgentCore | Community adapters (varying quality) |
| **Debugging** | Bedrock traces + CloudWatch | LangSmith (paid), custom logging |
| **Cost observability** | Bedrock metrics + inference profiles | Manual tracking |

---

### 1.8 Orchestration — Step Functions, Bedrock Flows, and Chaining Frameworks

![Orchestration Landscape](/diagrams/09-orchestration-landscape.svg)

When you need to coordinate multiple FM calls, tools, or processing steps, you have several orchestration options — from no-code visual builders to full programmatic control.

#### Orchestration Tools Compared

| Tool | Type | State Management | Complexity Cap | Cost Model | Best For |
|------|------|-----------------|----------------|------------|----------|
| **Bedrock Prompt Flows** | No-code visual | Managed (flow-level) | Medium (linear/branching) | Per-node execution | Prompt chains, simple branching, non-developers |
| **Bedrock Agents** | Managed autonomous | Managed (session) | High (dynamic reasoning) | Per-invocation | Autonomous tool-use, dynamic task decomposition |
| **Step Functions Standard** | Code/visual workflow | Built-in (execution history) | Very high (any pattern) | Per-state-transition | Long-running, auditable, complex branching, human-in-the-loop |
| **Step Functions Express** | Code/visual workflow | None (fire-and-forget) | High | Per-execution + duration | High-volume, short-lived (<5 min), event processing |
| **LangChain** | Python/JS library | Custom (memory classes) | Unlimited | Compute (self-managed) | Rapid prototyping, ecosystem integrations, any LLM |
| **LangGraph** | Python library (graphs) | Built-in (checkpoints) | Unlimited (cycles, branches) | Compute (self-managed) | Complex stateful workflows, agent loops, human-in-loop |
| **EventBridge + Lambda** | Event-driven | Stateless (event-per-invocation) | Medium | Per-event + Lambda | Loose coupling, async triggers, fan-out |

#### Decision Flow: Which Orchestration Tool?

```
What kind of orchestration?
│
├─ Sequential prompt chain (A → B → C)?
│   ├─ No code preferred → Bedrock Prompt Flows
│   ├─ Need conditional logic + loops → Bedrock Prompt Flows (supports both)
│   └─ Need complex error handling / retries → Step Functions
│
├─ Agent decides what to do dynamically?
│   ├─ Managed, simple → Bedrock Agents
│   └─ Custom logic, code-level → Strands Agents / LangGraph
│
├─ Multi-step workflow with human approval?
│   → Step Functions Standard (callback pattern)
│
├─ High-volume event processing (>1000/sec)?
│   → Step Functions Express or EventBridge + Lambda
│
├─ Long-running (minutes to hours)?
│   → Step Functions Standard (up to 1 year)
│   ✗ NOT Express (5 min max), NOT Lambda (15 min max)
│
├─ Need audit trail of every step?
│   → Step Functions Standard (built-in execution history)
│   ✗ NOT Express (no history retained)
│
├─ Rapid prototyping with any LLM provider?
│   → LangChain (fastest to experiment)
│   → Graduate to LangGraph when you need state/cycles
│
└─ Complex stateful graph with cycles (retry loops, reflection)?
    → LangGraph (native support for cycles + checkpointing)
    → Or Step Functions + custom state management
```

#### Bedrock Prompt Flows — Deep Dive

Prompt Flows is a **visual, no-code** builder for multi-step FM workflows. Think of it as "Step Functions for prompts" — but simpler and purpose-built for LLM chaining.

**Node Types:**

| Node | What It Does | Example Use |
|------|--------------|-------------|
| **Input** | Entry point; accepts user query or data | Start of every flow |
| **Prompt** | Sends prompt to an FM; receives response | Generate summary, classify intent, extract entities |
| **Condition** | Routes flow based on expression (if/else) | If sentiment = negative → escalation path |
| **Iterator** | Loops over array items, processing each | Process each chunk of a document separately |
| **Collector** | Gathers iterator outputs into single array | Combine all chunk summaries |
| **Knowledge Base** | Queries a Bedrock KB for retrieval | RAG step within a flow |
| **Agent** | Invokes a Bedrock Agent | Delegate complex reasoning to an agent |
| **Lambda** | Runs custom code | Data transformation, API calls, validation |
| **S3 Storage** | Read/write to S3 | Load input documents, store results |
| **Output** | Returns final result | End of flow |

**Key Capabilities:**
- **Conditional branching**: route based on FM output (e.g., classification result)
- **Iterative processing**: loop over arrays with parallel or sequential execution
- **Prompt chaining**: output of one prompt feeds into next prompt's input
- **Mixed nodes**: combine FM calls + Lambda + KB queries in one flow
- **Version management**: version flows, test before publishing
- **Guardrails integration**: attach guardrails to prompt nodes

**Architecture Example — Document Processing Flow:**
```
Input (PDF URL)
  → Lambda (extract text, split into sections)
  → Iterator (for each section)
      → Prompt ("Summarize this section: {section}")
      → Condition (if section mentions risks → flag)
  → Collector (gather all summaries)
  → Prompt ("Create executive summary from: {summaries}")
  → Output (final summary + risk flags)
```

**When Prompt Flows is NOT enough:**
- Need human approval gates → Step Functions
- Need to wait for external events → Step Functions
- Need execution longer than flow timeout → Step Functions
- Need cycles/loops that depend on external state → LangGraph
- Need to call non-AWS LLM providers → LangChain/LangGraph

#### Step Functions for GenAI — Patterns & Details

**Standard vs. Express:**

| Dimension | Standard Workflow | Express Workflow |
|-----------|-------------------|-----------------|
| Max duration | **1 year** | **5 minutes** |
| Execution history | Full (visible in console) | None (CloudWatch Logs only) |
| Execution semantics | Exactly-once | At-least-once (sync) or at-most-once (async) |
| Pricing | Per state transition ($0.025/1000) | Per execution + duration |
| Best for gen AI | Long pipelines, human-in-loop, audit-required | High-volume pre-processing, classification, routing |
| State limit | 256 KB payload | 256 KB payload |

**Key Step Functions Patterns for GenAI:**

**1. Prompt Chain (sequential):**
```json
{
  "StartAt": "ClassifyIntent",
  "States": {
    "ClassifyIntent": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:classify",
      "Next": "RouteByIntent"
    },
    "RouteByIntent": {
      "Type": "Choice",
      "Choices": [
        { "Variable": "$.intent", "StringEquals": "refund", "Next": "HandleRefund" },
        { "Variable": "$.intent", "StringEquals": "info", "Next": "HandleInfo" }
      ],
      "Default": "Fallback"
    },
    "HandleRefund": { "Type": "Task", "Resource": "...", "End": true },
    "HandleInfo": { "Type": "Task", "Resource": "...", "End": true },
    "Fallback": { "Type": "Task", "Resource": "...", "End": true }
  }
}
```

**2. Parallel fan-out (process multiple docs simultaneously):**
```
Map State (maxConcurrency: 10)
  → For each document in array:
      → Lambda (chunk + embed)
      → Bedrock (generate summary)
  → Collect all results
  → Lambda (aggregate into final report)
```

**3. Human-in-the-loop (callback pattern):**
```
Generate Draft (Bedrock)
  → Send for Review (Task with waitForTaskToken)
      → API Gateway notifies reviewer
      → Reviewer approves/rejects via callback URL
      → Step Functions resumes with decision
  → Choice: approved → publish | rejected → revise loop
```

**4. Circuit breaker (resilient FM calls):**
```
Try Primary Model (Bedrock)
  → Catch: ThrottlingException
      → Increment failure counter (DynamoDB)
      → Choice: if failures > 3 → Fallback Model
      → Wait (exponential backoff)
      → Retry Primary
```

**5. Batch processing with quality gate:**
```
Map State (process 1000 docs)
  → Generate summaries (Bedrock Batch or parallel Lambda)
  → Sample quality check (LLM-as-judge on 5% sample)
  → Choice: quality < threshold → alert + reprocess failures
           quality ≥ threshold → write to S3
```

#### EventBridge — Event-Driven AI Patterns

EventBridge connects business events to AI workflows without tight coupling.

**Common Patterns:**

| Trigger Event | AI Workflow | Implementation |
|---------------|-------------|----------------|
| New support ticket created | Agent classifies + routes | EventBridge rule → Lambda → Bedrock Agent |
| Document uploaded to S3 | RAG ingestion pipeline | S3 → EventBridge → Step Functions (chunk → embed → index) |
| Scheduled (daily 2am) | Batch summarization | EventBridge Schedule → Step Functions → Bedrock Batch |
| Model evaluation score drops | Alert + rollback | CloudWatch Alarm → EventBridge → SNS + Lambda (rollback) |
| Customer feedback received | Sentiment analysis + routing | EventBridge → Lambda → Comprehend → conditional routing |

**Why EventBridge over direct invocation:**
- Loose coupling: AI components evolve independently
- Fan-out: one event triggers multiple consumers
- Filtering: rules route only relevant events to AI workflows
- Retry: built-in dead-letter queues for failed deliveries
- Audit: every event logged

#### LangChain & LangGraph — When and Why

**LangChain** is the most popular open-source framework for LLM applications. It provides:
- **Chains**: sequential composition of LLM calls + tools
- **Agents**: LLM decides which tool to call (similar to Bedrock Agents but self-managed)
- **Memory**: conversation history management (buffer, summary, vector-backed)
- **Retrievers**: abstractions over vector stores for RAG
- **Callbacks**: hooks for logging, tracing, streaming

**LangGraph** extends LangChain with:
- **Stateful graphs**: nodes = steps, edges = transitions (including cycles)
- **Checkpointing**: save/resume workflow state (enables human-in-loop)
- **Cycles**: agent can loop back (retry, reflect, refine) — impossible in pure chains
- **Parallel branches**: execute multiple paths simultaneously
- **Subgraphs**: modular, composable workflow components

**When to use each:**

| Scenario | Tool | Why |
|----------|------|-----|
| Quick prototype, explore different models | LangChain | Fastest setup, swap models easily |
| Simple RAG app | LangChain | Built-in retrievers + chains |
| Agent that retries/reflects on failures | LangGraph | Needs cycles (LangChain chains are linear) |
| Complex multi-step with conditional paths | LangGraph | Graph structure handles branching natively |
| Need human approval mid-workflow | LangGraph (checkpoints) or Step Functions | Both support pause/resume |
| Production on AWS with compliance | Step Functions + Bedrock | Audit trail, IAM, managed infrastructure |
| Provider-agnostic (OpenAI + Anthropic + local) | LangChain/LangGraph | Abstract over any provider |
| No-code, business users building flows | Bedrock Prompt Flows | Visual builder, no Python needed |

**LangChain on AWS — Integration Pattern:**
```
LangChain app (Python)
  → ChatBedrock (LLM via Bedrock API)
  → AmazonKnowledgeBasesRetriever (RAG via Bedrock KB)
  → Tools via MCP or custom functions
  → Deploy on: Lambda, ECS, or AgentCore
  → Observe with: LangSmith (paid) or CloudWatch + X-Ray
```

**LangGraph on AWS — Stateful Agent:**
```python
from langgraph.graph import StateGraph, END

# Define state
class AgentState(TypedDict):
    messages: list
    next_action: str

# Build graph
graph = StateGraph(AgentState)
graph.add_node("reason", reasoning_node)
graph.add_node("act", action_node)
graph.add_node("reflect", reflection_node)

# Add edges (including cycles)
graph.add_edge("reason", "act")
graph.add_conditional_edges("act", should_reflect,
    {"yes": "reflect", "no": END})
graph.add_edge("reflect", "reason")  # cycle back!

app = graph.compile(checkpointer=MemorySaver())
```

#### Complete Orchestration Decision Matrix

| Dimension | Prompt Flows | Bedrock Agents | Step Functions | LangChain | LangGraph |
|-----------|-------------|----------------|----------------|-----------|-----------|
| **Paradigm** | Visual flow | Autonomous agent | State machine | Chains | Stateful graph |
| **Code required** | No | No (console) | ASL JSON/YAML | Python/JS | Python |
| **Cycles (loops)** | Iterator only | Built-in (ReAct) | Yes (explicit) | No | Yes (native) |
| **Human-in-loop** | No | Limited | Yes (callbacks) | Custom | Yes (checkpoints) |
| **Max duration** | Minutes | Minutes | 1 year | Unlimited (self-managed) | Unlimited |
| **State persistence** | Flow-managed | Session | Execution history | Custom (memory) | Checkpoints |
| **Error handling** | Basic | Automatic retry | Rich (Catch/Retry) | Custom try/except | Custom |
| **Parallel exec** | Iterator | No | Map + Parallel states | Async | Parallel branches |
| **Audit trail** | CloudWatch | Agent traces | Full execution history | LangSmith / custom | LangSmith / custom |
| **LLM providers** | Bedrock only | Bedrock only | Any (via Lambda) | Any | Any |
| **Guardrails** | Attach to nodes | Attach to agent | Custom (invoke API) | Custom | Custom |
| **Typical latency** | Seconds | Seconds-minutes | Seconds-hours | Seconds | Seconds-minutes |
| **Cost** | Per-node | Per-invocation | Per-transition | Compute only | Compute only |

#### Key Exam Signals for Orchestration

| Signal in Question | Points To |
|--------------------|-----------|
| "No-code" + "prompt chain" | Bedrock Prompt Flows |
| "Visual builder" + "business users" | Bedrock Prompt Flows |
| "Conditional branching based on FM output" | Prompt Flows (Condition node) or Step Functions (Choice) |
| "Human approval required" | Step Functions (callback) |
| "Long-running" (>5 min) | Step Functions Standard |
| "High volume" + "short-lived" | Step Functions Express |
| "Audit trail" + "compliance" | Step Functions Standard |
| "Event-driven" + "loose coupling" | EventBridge |
| "Agent autonomously decides" | Bedrock Agents |
| "Retry/reflect loop" or "self-improving" | LangGraph (cycles) |
| "Any LLM provider" | LangChain / LangGraph |
| "Stateful conversation graph" | LangGraph |
| "Process array of items in parallel" | Step Functions Map state |
| "Circuit breaker" + "fallback model" | Step Functions (Catch + Choice) |

---

### 1.9 Cross-Account & Cross-Region Bedrock Access Patterns

![Cross-Account and Cross-Region Bedrock Access](/diagrams/11-cross-account-region.svg)

Enterprise architectures typically centralize AI services in a dedicated account and serve multiple consumer accounts across regions. Understanding how Bedrock handles cross-boundary access is critical.

#### Key Concepts: Inference Profiles

Bedrock uses **Inference Profiles** as the mechanism for both cross-region routing and cost allocation. There are two types — confusingly named but very different:

| Type | What It Is | Created By | Purpose |
|------|-----------|------------|---------|
| **System-defined Inference Profile** | Pre-configured cross-region routing profile | AWS (built-in) | Route requests across regions for higher throughput and availability |
| **Application Inference Profile** | Custom tag-based profile you create | You | Cost allocation (tag by team/app/tenant) + optional routing config |

**System-defined profiles** give you a model ID that automatically distributes requests across multiple regions within your geography (e.g., `us.*` routes across us-east-1, us-west-2). You invoke this ID instead of a region-specific model ID.

**Application inference profiles** let you create a named profile, attach cost-allocation tags, and optionally point it at a system-defined profile for cross-region routing. They're primarily for **cost tracking per team/app**.

```
System-Defined Inference Profile (cross-region):
  us.anthropic.claude-sonnet-4-6-v1
    → routes to us-east-1, us-west-2, etc. automatically
    → higher aggregate throughput than single-region

Application Inference Profile (cost allocation):
  "team-alpha-profile" → tags: team=alpha, app=chatbot
    → can reference a system-defined profile (get both cross-region + tagging)
    → or reference a specific model in a specific region
```

#### Cross-Region Inference — How It Actually Works

```
┌───────────────────────────────────────────────────────────────────┐
│  Your Application (us-east-1)                                     │
│                                                                   │
│  InvokeModel(modelId="us.anthropic.claude-sonnet-4-6-v1")         │
│       │                                                           │
│       ▼                                                           │
│  Bedrock Cross-Region Routing                                     │
│       │                                                           │
│       ├─── us-east-1 (capacity available?) ──→ ✓ serve here       │
│       │                                                           │
│       ├─── us-west-2 (overflow) ──→ route if east-1 is full       │
│       │                                                           │
│       └─── us-east-2 (overflow) ──→ route if others are full      │
│                                                                   │
│  Response returns to caller in us-east-1 regardless of where      │
│  inference executed. Transparent to the application.              │
└───────────────────────────────────────────────────────────────────┘
```

**Key points:**
- You call the system-defined profile ID (e.g., `us.anthropic.claude-sonnet-4-6-v1`) instead of the region-specific model ID
- Routing is automatic — Bedrock handles it based on available capacity
- Your application doesn't change; response comes back normally
- Data stays within the geographic boundary (US models stay in US regions)
- **No cost difference** — same per-token pricing regardless of which region serves the request
- Purpose is **availability + throughput**, not data residency

**When to use Cross-Region Inference:**
- Production workloads needing resilience against regional capacity constraints
- High-throughput applications that might hit single-region limits
- When you want higher aggregate token-per-minute throughput

**When NOT to use:**
- Data residency requirements mandate a specific region → use region-specific model ID
- You need deterministic routing for debugging → use region-specific model ID
- You're using Custom Model Import (only available in the region where imported)

#### Cross-Account Bedrock Access

For enterprise multi-account architectures (central AI account + consumer accounts):

**Pattern 1: Cross-Account IAM Role Assumption**

```
┌─────────────────────┐         ┌──────────────────────────┐
│ Consumer Account A  │         │ Central AI Account       │
│                     │         │                          │
│ App → AssumeRole ───┼────────►│ bedrock-consumer-role    │
│                     │  STS    │   ├─ InvokeModel: allow  │
│                     │         │   ├─ Specific models     │
│                     │         │   └─ Condition: sourceVpc│
│                     │         │                          │
│                     │         │ Bedrock (models enabled) │
└─────────────────────┘         └──────────────────────────┘
```

**How it works:**
1. Central AI account enables Bedrock models and creates IAM roles for consumers
2. Consumer accounts assume the role via STS (`sts:AssumeRole`)
3. Role's trust policy specifies which accounts/roles can assume it
4. Role's permission policy scopes access (specific models, guardrails required, etc.)
5. Consumer gets temporary credentials → calls Bedrock in the central account

**IAM Trust Policy (central account role):**
```json
{
  "Effect": "Allow",
  "Principal": {
    "AWS": [
      "arn:aws:iam::111111111111:role/AppRole",
      "arn:aws:iam::222222222222:role/AppRole"
    ]
  },
  "Action": "sts:AssumeRole",
  "Condition": {
    "StringEquals": {
      "aws:PrincipalOrgID": "o-xxxxxxxxxx"
    }
  }
}
```

**Pattern 2: Bedrock Model Resource Policy (newer approach)**

Some Bedrock resources support resource-based policies, allowing direct cross-account access without role assumption:

```
┌─────────────────────┐         ┌─────────────────────────┐
│ Consumer Account A  │         │ Central AI Account      │
│                     │         │                         │
│ App (own IAM role) ─┼────────►│ Bedrock Resource Policy │
│   direct call       │         │   "Allow Account A to   │
│                     │         │    invoke model X"      │
│                     │         │                         │
└─────────────────────┘         └─────────────────────────┘
```

**Supported for:**
- Custom models (fine-tuned models can be shared via resource policy)
- Provisioned throughput (share capacity across accounts)
- Knowledge Bases (cross-account access to centralized KB)

**NOT supported for:**
- On-demand base models (each account must enable models independently)

**Pattern 3: Each Account Enables Models Independently (simplest)**

```
┌─────────────────────┐    ┌─────────────────────┐    ┌──────────────────┐
│ Account A           │    │ Account B           │    │ Account C        │
│ Bedrock enabled     │    │ Bedrock enabled     │    │ Bedrock enabled  │
│ Models: Claude,Nova │    │ Models: Claude only │    │ Models: All      │
│ Own guardrails      │    │ Own guardrails      │    │ Own guardrails   │
│ Own logging         │    │ Own logging         │    │ Own logging      │
└─────────────────────┘    └─────────────────────┘    └──────────────────┘
```

**When to use:** small org, no shared custom models, teams want full independence.
**Drawback:** duplicated configuration, no centralized governance, can't share custom/fine-tuned models.

#### Multi-Account Architecture Decision

| Requirement | Pattern | Why |
|-------------|---------|-----|
| Share fine-tuned custom models across accounts | Resource Policy on custom model | Avoids retraining in each account |
| Centralized guardrails enforcement | Cross-account role + SCP (must include guardrail) | Single point of control |
| Centralized logging & audit | Cross-account role (logs stay in central) | Compliance needs single audit trail |
| Cost allocation per team/account | Application Inference Profiles (tags) | Each account/team gets tagged usage |
| Maximum team independence | Independent accounts (Pattern 3) | No cross-account complexity |
| Share provisioned throughput capacity | Resource Policy on provisioned throughput | Avoid paying for capacity per-account |
| Central KB shared across accounts | Cross-account KB access (resource policy) | Single knowledge base, multiple consumers |

#### Cross-Region Data Considerations

| Component | Cross-Region Behavior | Implication |
|-----------|----------------------|-------------|
| **Bedrock models (on-demand)** | Available in model-supported regions | Enable per-region; use cross-region inference for routing |
| **Custom/imported models** | Only in the region where created/imported | Must re-import if needed in another region |
| **Knowledge Bases** | Regional (vector store + data in one region) | KB and its vector store must be in same region |
| **Guardrails** | Regional | Create in each region where models are invoked |
| **Invocation logs** | Regional (S3 bucket / CloudWatch in that region) | Use S3 Cross-Region Replication for centralized audit |
| **Prompt Management** | Regional | Templates available only in the region created |
| **Inference Profiles (system)** | Multi-region by design | The whole point — routes across regions |
| **Inference Profiles (application)** | Regional (created in one region) | Tag costs in the region where profile lives |

**Multi-Region RAG pattern:**
```
Region A: KB + Vector Store + Documents (source of truth)
Region B: Application calling Bedrock FM
  └─ Option 1: Call KB in Region A cross-region (added latency)
  └─ Option 2: Replicate vector store to Region B (data sync complexity)
  └─ Option 3: Use Region A for both KB + FM (simplest, single-region)
```

#### Inference Profiles vs. Cross-Region Inference — Clearing the Confusion

| Question | Answer |
|----------|--------|
| "I want higher throughput / avoid throttling" | Use **system-defined inference profile** (cross-region routing) |
| "I want to track cost by team" | Use **application inference profile** (tags) |
| "I want both" | Create application profile → point it at a system-defined profile |
| "I want guaranteed capacity" | Use **Provisioned Throughput** (not inference profiles) |
| "I want to use a model not in my region" | Use **system-defined profile** for that model (routes to available regions) |
| "I want to control exactly which region serves my request" | Use **region-specific model ID** (don't use profiles) |

#### Complete Enterprise Pattern

```
┌─ AWS Organization ────────────────────────────────────────────────────┐
│                                                                       │
│  ┌─ Central AI Account ────────────────────────────────────────────┐  │
│  │                                                                 │  │
│  │  • All models enabled                                           │  │
│  │  • Custom models (fine-tuned + imported)                        │  │
│  │  • Central Knowledge Bases                                      │  │
│  │  • Guardrails (shared via cross-account role)                   │  │
│  │  • Invocation logging → central S3 bucket                       │  │
│  │  • Application inference profiles (per-team tags)               │  │
│  │  • IAM roles for each consumer account                          │  │
│  │  • VPC endpoint (PrivateLink)                                   │  │
│  │                                                                 │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│          ▲                    ▲                    ▲                  │
│          │ AssumeRole         │ AssumeRole         │ AssumeRole       │
│          │                    │                    │                  │
│  ┌───────┴──────┐    ┌───────┴──────┐    ┌───────┴──────┐             │
│  │ Team A Acct  │    │ Team B Acct  │    │ Team C Acct  │             │
│  │ (chatbot)    │    │ (analytics)  │    │ (code gen)   │             │
│  │              │    │              │    │              │             │
│  │ App → assume │    │ App → assume │    │ App → assume │             │
│  │ central role │    │ central role │    │ central role │             │
│  └──────────────┘    └──────────────┘    └──────────────┘             │
│                                                                       │
│  SCP: deny Bedrock unless via VPC endpoint + guardrail attached       │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

**Benefits of this pattern:**
- Single place to enable/manage models
- Shared custom models without re-training per account
- Centralized audit trail (all invocation logs in one bucket)
- Cost allocation via application inference profiles (tagged by team)
- SCP enforces: must use VPC endpoint, must attach guardrail
- Teams get scoped access (only the models/KB they need)

#### Key Exam Signals

| Signal in Question | Answer Points To |
|--------------------|-----------------|
| "Higher throughput" + "avoid throttling" | Cross-Region Inference (system inference profile) |
| "Track cost per team" or "cost allocation" | Application Inference Profiles (tags) |
| "Share fine-tuned model across accounts" | Resource-based policy on custom model |
| "Centralized governance" + "multi-account" | Central AI account + cross-account IAM roles + SCP |
| "Deny Bedrock access unless VPC endpoint" | SCP with `aws:sourceVpce` condition |
| "Model not available in my region" | System-defined inference profile (routes to region with model) |
| "Data must stay in specific region" | Region-specific model ID (NOT cross-region inference) |
| "Share provisioned capacity across accounts" | Resource policy on provisioned throughput |
| "Consolidated logging" | Central account invocation logging + S3 replication |

---

### 1.10 Security & Guardrails Selection

| Threat | Control | Service |
|--------|---------|---------|
| Prompt injection | Content filters + prompt attack detection | Bedrock Guardrails (Standard tier) |
| Toxic/harmful output | Content filters (hate, violence, sexual, misconduct) | Bedrock Guardrails |
| Off-topic usage | Denied topics | Bedrock Guardrails |
| PII in input/output | Sensitive information filters + regex | Bedrock Guardrails + Comprehend |
| Hallucination | Contextual grounding checks | Bedrock Guardrails + Knowledge Bases |
| Logical errors | Automated Reasoning checks | Bedrock Guardrails |
| Data exfiltration | VPC endpoints (PrivateLink) + IAM | Network layer |
| Unauthorized model access | IAM roles (evaluation / general / fine-tuned / specialized) | IAM |
| Audit & compliance | Invocation logging + CloudTrail | S3 + CloudWatch Logs |

**Defense-in-Depth Layers:**
```
1. Network: VPC endpoints, no public internet for FM calls
2. Identity: IAM roles per use case, least privilege
3. Input: Guardrails content filters + custom pre-processing
4. Model: Guardrails denied topics + grounding checks
5. Output: Guardrails + post-processing Lambda
6. Audit: CloudTrail + invocation logs + CloudWatch
```

---

### 1.11 Cost Optimization Decisions

![Model Cascading Pattern](/diagrams/06-model-cascading.svg)

| Technique | Savings | Trade-off |
|-----------|---------|-----------|
| **Model cascading** (small → large) | 40-70% | Added latency for routing; complexity |
| **Prompt caching** (Bedrock) | Up to 90% on cached portions | Only helps repeated context |
| **Batch inference** | ~50% vs on-demand | Not real-time; hours of latency |
| **Provisioned throughput** | Predictable cost at scale | Commit required; waste if underused |
| **Prompt compression** | 20-40% token reduction | Slight quality risk |
| **Semantic caching** | High for repeated queries | Cache invalidation complexity |
| **Smaller embeddings dimensions** | Storage + compute savings | Minor recall trade-off |

---

## Part 2: Scenario-Pattern Cards

### Domain 1: FM Integration, Data Management, and Compliance

![RAG Pipeline End-to-End](/diagrams/01-rag-pipeline.svg)

---

#### Card 1.1: Enterprise Document Q&A

**Scenario:** Organization needs employees to ask questions against 10,000+ internal documents (PDF, Word, HTML) with access controls.

**Pattern:** Managed RAG with Bedrock Knowledge Bases

**Architecture:**
```
S3 (docs) → Bedrock KB (chunk + embed + index) → OpenSearch Serverless
User Query → Bedrock KB RetrieveAndGenerate → FM → Response with citations
```

**Key Services:** Bedrock Knowledge Bases, S3, OpenSearch Serverless, IAM

**Why this pattern:**
- Fully managed ingestion, chunking, embedding, sync
- Built-in citation/attribution for grounding
- Automatic re-sync when documents change

**Watch out for:**
- Per-user permissions need custom metadata filtering or use Q Business instead
- Large docs benefit from hierarchical chunking over fixed-size

---

#### Card 1.2: Multi-Source Hybrid Search RAG

**Scenario:** Need to combine keyword search (product SKUs, codes) with semantic search across technical manuals.

**Pattern:** Custom RAG with OpenSearch hybrid search

**Architecture:**
```
Ingestion: Docs → Lambda (chunk) → Bedrock (embed) → OpenSearch (BM25 + kNN index)
Query: User → Lambda (embed query) → OpenSearch (hybrid: BM25 + kNN + reranker) → Bedrock FM
```

**Key Services:** OpenSearch Service, Lambda, Bedrock (embeddings + FM + reranker)

**Why this pattern:**
- Hybrid search catches both exact matches (SKUs) and semantic similarity
- Reranker improves precision without re-embedding
- Full control over scoring weights

---

#### Card 1.3: Real-Time Data RAG

**Scenario:** Customer support needs answers from a knowledge base that updates every few minutes (live tickets, status pages).

**Pattern:** Streaming ingestion with incremental sync

**Architecture:**
```
Source → EventBridge/DynamoDB Streams → Lambda (chunk + embed) → OpenSearch
                                                                    ↑ incremental upsert
User Query → Bedrock KB (or custom retrieval) → FM
```

**Key Services:** EventBridge, Lambda, DynamoDB Streams, OpenSearch, Bedrock

**Why this pattern:**
- Near real-time freshness vs. scheduled batch sync
- Incremental updates avoid full re-indexing cost

---

#### Card 1.4: Cross-Region FM Resilience

**Scenario:** Production app must maintain <1% downtime for FM inference across regions.

**Pattern:** Cross-Region Inference + circuit breaker

**Architecture:**
```
App → Bedrock Cross-Region Inference (automatic routing)
     └─ Fallback: Step Functions circuit breaker → secondary model/region
```

**Key Services:** Bedrock Cross-Region Inference, Step Functions, CloudWatch Alarms

**Why this pattern:**
- Cross-Region Inference handles regional capacity issues automatically
- Circuit breaker degrades gracefully to smaller/different model if all regions fail

---

#### Card 1.5: Prompt Governance at Scale

**Scenario:** 50+ teams building gen AI features; need consistent prompt quality, versioning, and audit.

**Pattern:** Centralized prompt management

**Architecture:**
```
Prompt Authors → Bedrock Prompt Management (templates + versions + approval)
Apps → Reference prompt by ID + version → Bedrock invokes with template
Audit: CloudTrail logs all prompt usage; CloudWatch tracks effectiveness
```

**Key Services:** Bedrock Prompt Management, CloudTrail, CloudWatch

**Why this pattern:**
- Parameterized templates prevent prompt drift
- Version pinning prevents accidental regressions
- Centralized audit for compliance

---

### Domain 2: Implementation and Integration

---

#### Card 2.1: Autonomous Task Agent

![Bedrock Agent Orchestration](/diagrams/05-bedrock-agent.svg)

**Scenario:** Build an agent that can book meetings, check calendars, and send emails on behalf of users.

**Pattern:** Bedrock Agent with action groups

**Architecture:**
```
User (natural language) → Bedrock Agent
  ├─ Orchestration: breaks down task
  ├─ Action Group 1: Calendar API (Lambda)
  ├─ Action Group 2: Email API (Lambda)
  └─ Knowledge Base: company meeting policies
Agent → structured API calls → returns confirmation
```

**Key Services:** Bedrock Agents, Lambda (action groups), Bedrock KB

**Why this pattern:**
- Managed orchestration (ReAct loop built-in)
- Action groups define available tools with OpenAPI schemas
- KB augments with policy knowledge

**Safety:** IAM scopes Lambda to only allowed APIs; timeout limits; Guardrails filter

---

#### Card 2.2: Multi-Agent Collaboration

**Scenario:** Complex research task requiring a planner agent, researcher agent, and writer agent working together.

**Pattern:** Multi-agent with AgentCore / Agent Squad

**Architecture:**
```
Supervisor Agent (planning + delegation)
  ├─ Research Agent (web search tools, KB access)
  ├─ Analysis Agent (data processing, calculations)
  └─ Writer Agent (synthesis, formatting)
AgentCore: memory, session management, coordination
```

**Key Services:** Bedrock AgentCore, Strands Agents, Agent Squad

**Why this pattern:**
- Specialized agents outperform one generalist agent
- AgentCore handles memory + state across agents
- Each agent has minimal tool access (least privilege)

---

#### Card 2.3: Human-in-the-Loop Workflow

**Scenario:** AI drafts customer responses, but high-value cases need human approval before sending.

**Pattern:** Step Functions with callback + approval gate

**Architecture:**
```
Customer Query → Lambda (classify priority)
  ├─ Low priority → Bedrock Agent → auto-respond
  └─ High priority → Bedrock Agent (draft) → Step Functions (wait for callback)
       → Human reviews in UI → Approve/Edit → Send
```

**Key Services:** Step Functions (callback pattern), Lambda, Bedrock, API Gateway (WebSocket)

**Why this pattern:**
- Step Functions natively supports wait-for-callback
- Business logic separates auto-respond from human review
- Full audit trail of decisions

---

#### Card 2.4: Streaming Response with GenAI Gateway

![GenAI Gateway Pattern](/diagrams/07-genai-gateway.svg)

**Scenario:** Multiple teams need FM access with consistent auth, logging, rate limiting, and model routing.

**Pattern:** Centralized GenAI gateway

**Architecture:**
```
Team Apps → API Gateway (auth, rate limit, request validation)
  → Lambda (routing logic: model selection based on content/cost)
  → Bedrock InvokeModelWithResponseStream
  → API Gateway WebSocket / SSE → Client
Observability: X-Ray traces, CloudWatch metrics, invocation logs
```

**Key Services:** API Gateway, Lambda, Bedrock streaming API, X-Ray, CloudWatch

**Why this pattern:**
- Single entry point for governance, logging, cost allocation
- Model routing without app code changes (use AppConfig for dynamic config)
- Streaming for real-time UX

---

#### Card 2.5: MCP Tool Integration

![MCP Lambda Layer Pattern](/diagrams/03-mcp-lambda-layer.svg)

**Scenario:** Agent needs access to diverse tools (database, file system, APIs) via standardized protocol.

**Pattern:** MCP servers (stateless on Lambda, stateful on ECS)

**Architecture:**
```
Agent (MCP Client) → MCP Protocol
  ├─ Lambda MCP Server (lightweight: search, lookups)
  ├─ ECS MCP Server (complex: DB connections, long-running)
  └─ External MCP Server (third-party tools)
```

**Key Services:** Lambda, ECS, Bedrock AgentCore (MCP client), API Gateway

**Why this pattern:**
- Standardized tool interface across any agent framework
- Lambda for stateless (cost efficient); ECS for stateful
- Tools are reusable across agents

**MCP Transport Modes:**

| Transport | How It Works | Use When |
|-----------|--------------|----------|
| **STDIO** | Client spawns MCP server as subprocess; communicates via stdin/stdout | Co-located (same environment): lowest latency, simplest |
| **Streamable HTTP** | MCP server runs as independent HTTP endpoint; client POSTs JSON-RPC | Remote/network-separated: Lambda→ECS, cross-service |

**Lambda Layer + STDIO Pattern (co-located MCP):**

```
┌──────────────────────────────────────────────────────┐
│ Lambda Execution Environment                         │
│                                                      │
│  ┌──────────────────────────┐                        │
│  │ Client Lambda (handler)  │                        │
│  │  - Agent logic           │                        │
│  │  - MCP client            │──── stdin/stdout ────┐ │
│  └──────────────────────────┘                      │ │
│                                                    ▼ │
│  ┌──────────────────────────┐                        │
│  │ Lambda Layer (/opt/)     │                        │
│  │  - MCP server code       │                        │
│  │  - Tool implementations  │                        │
│  │  - Spawned as subprocess │                        │
│  └──────────────────────────┘                        │
└──────────────────────────────────────────────────────┘
```

**How it works:**
1. MCP server is packaged as a **Lambda Layer** (shared code available at `/opt/` in the execution environment)
2. Client Lambda function spawns the MCP server as a **local subprocess** at invocation time
3. Communication happens over **STDIO** (stdin/stdout) — no network call, no HTTP overhead
4. Each Lambda invocation starts fresh — inherently stateless
5. Uses `StdioServerParameters` from Strands Agents SDK to configure the connection

**Why STDIO over HTTP for co-located:**
- No network stack overhead (no TCP, no HTTP parsing)
- No port management or service discovery
- Simpler error handling (process lifecycle = connection lifecycle)
- Lower latency (~ms subprocess spawn vs. HTTP round-trip)
- The MCP spec recommends: "Clients SHOULD support stdio whenever possible"

**When to use each deployment:**

| MCP Server Location | Transport | Lambda Pattern |
|---------------------|-----------|----------------|
| Same Lambda (via Layer) | STDIO | Client spawns server subprocess locally |
| Separate Lambda | Streamable HTTP | Client makes HTTP call to server Lambda's function URL |
| ECS/Fargate | Streamable HTTP | Client calls server's HTTP endpoint; server maintains state |
| AgentCore prebuilt | Managed | AgentCore handles transport internally |

**Code example (Strands Agents + STDIO):**
```python
from mcp import StdioServerParameters, stdio_client
from strands.tools.mcp import MCPClient

# MCP server is in Lambda Layer at /opt/mcp-server/
mcp_client = MCPClient(
    lambda: stdio_client(
        StdioServerParameters(
            command="/opt/mcp-server/run.sh",
            args=["--tools", "search,lookup"]
        )
    )
)

with mcp_client:
    tools = mcp_client.list_tools_sync()
    agent = Agent(tools=tools)
    response = agent("Find the latest documentation for service X")
```

**Sources:** [MCP Transport Specification](https://modelcontextprotocol.io/docs/concepts/transports), Strands Agents SDK MCP integration, AWS serverless agentic AI patterns

---

### Domain 3: AI Safety, Security, and Governance

---

![Defense-in-Depth for Generative AI](/diagrams/04-defense-in-depth.svg)

#### Card 3.1: PII Protection in Customer-Facing App

**Scenario:** Chatbot handles customer queries that may contain SSN, credit cards, addresses.

**Pattern:** Multi-layer PII detection and masking

**Architecture:**
```
User Input → Comprehend (PII detection) → Mask before sending to FM
          → Bedrock Guardrails (sensitive info filter as second layer)
FM Response → Guardrails (output filter) → Masked response to user
Logs: Invocation logs with PII redacted before storage
```

**Key Services:** Comprehend, Bedrock Guardrails, CloudWatch Logs (with filtering)

**Why this pattern:**
- Defense-in-depth: Comprehend catches PII pre-FM; Guardrails catches in response
- Masking preserves conversation flow while protecting data
- Redacted logs remain useful for debugging without compliance risk

---

#### Card 3.2: Preventing Hallucination in Regulated Industry

**Scenario:** Financial services app must not generate investment advice or state inaccurate facts.

**Pattern:** Grounding + denied topics + automated reasoning

**Architecture:**
```
User Query → Bedrock Guardrails (denied topics: investment advice)
  → Bedrock KB (retrieve grounding documents)
  → FM generates response
  → Guardrails: contextual grounding check (is response supported by sources?)
  → Guardrails: automated reasoning (logical consistency)
  → Response with citations
```

**Key Services:** Bedrock Guardrails (all checks), Bedrock KB, CloudWatch

**Why this pattern:**
- Denied topics block forbidden categories entirely
- Grounding check verifies response against retrieved sources
- Automated reasoning catches logical errors
- Citations provide traceability for audit

---

#### Card 3.3: Multi-Tenant FM Access Governance

**Scenario:** Platform serves multiple business units; need isolation, cost tracking, and differentiated access.

**Pattern:** IAM role separation + resource tagging + invocation logging

**Architecture:**
```
BU-A (evaluation role) → can access sandbox models only
BU-B (general role) → can access approved production models
BU-C (specialized role) → can access high-cost models
All → VPC endpoint (PrivateLink) → Bedrock
Logging: Per-BU cost tags, CloudTrail, invocation logs to per-BU S3 prefix
```

**Key Services:** IAM, PrivateLink, CloudTrail, S3, Cost Explorer (tags)

---

### Domain 4: Operational Efficiency and Optimization

---

#### Card 4.1: Cost-Optimized High-Volume Summarization

**Scenario:** Process 100K documents/day for summarization; cost is primary concern.

**Pattern:** Batch inference + model cascading

**Architecture:**
```
Documents → S3 → Bedrock Batch Inference (Nova Lite for bulk)
  ├─ Quality check (sample) → if below threshold → re-process with Nova Pro
  └─ Results → S3
Cost: Batch = ~50% cheaper; Nova Lite = fraction of larger model cost
```

**Key Services:** Bedrock Batch Inference, S3, Lambda (quality sampling)

**Why this pattern:**
- Batch inference is cheapest option (not real-time)
- Small model handles majority; only escalate failures
- Sample-based QA avoids evaluating all outputs

---

#### Card 4.2: Low-Latency Chat with Caching

**Scenario:** Customer-facing chatbot with many repeated/similar questions; need <2s response time.

**Pattern:** Semantic cache + streaming + prompt caching

**Architecture:**
```
User Query → Lambda (semantic similarity check against cache)
  ├─ Cache hit (>0.95 similarity) → return cached response
  └─ Cache miss → Bedrock (with prompt caching for system prompt)
       → Streaming response → cache result
Cache: ElastiCache or DynamoDB with embedding similarity
```

**Key Services:** Bedrock (prompt caching + streaming), ElastiCache/DynamoDB, Lambda

**Why this pattern:**
- Prompt caching saves on repeated system prompt tokens (up to 90%)
- Semantic cache eliminates redundant FM calls entirely
- Streaming improves perceived latency

---

#### Card 4.3: Monitoring GenAI Application Health

**Scenario:** Production gen AI app needs comprehensive observability.

**Pattern:** Full-stack gen AI observability

**Metrics to Track:**
```
Operational:     Latency (p50/p95/p99), error rate, throttling rate
Token:           Input/output tokens per request, cost per request
Quality:         Hallucination rate (grounding score), user feedback rating
Retrieval:       Retrieval latency, relevance scores, empty results rate
Agent:           Task completion rate, tool call success rate, steps per task
Business:        Resolution rate, escalation rate, user satisfaction
```

**Key Services:** CloudWatch (custom metrics + dashboards), X-Ray (traces), Bedrock invocation logs

---

### Domain 5: Testing, Validation, and Troubleshooting

---

#### Card 5.1: RAG Quality Evaluation

**Scenario:** Need to measure and improve RAG pipeline quality before production.

**Pattern:** Multi-dimensional RAG evaluation

**Metrics:**
```
Retrieval Quality:
  - Context relevance: are retrieved chunks relevant to query?
  - Context recall: did we retrieve all needed information?
  - Chunk utilization: how much retrieved context was actually used?

Generation Quality:
  - Faithfulness: is response supported by retrieved context? (grounding)
  - Answer relevance: does response actually answer the question?
  - Completeness: are all aspects of the query addressed?
```

**Implementation:** Bedrock Model Evaluation (RAG evaluation), LLM-as-a-judge, golden test datasets

**Key Services:** Bedrock Evaluation, CloudWatch (tracking over time)

---

#### Card 5.2: Agent Evaluation Framework

**Scenario:** Need to validate agent performs tasks correctly before deployment.

**Pattern:** Multi-level agent testing

**Evaluation Layers:**
```
1. Tool-level: Does each tool return correct results? (unit tests)
2. Reasoning: Does agent choose correct tools in correct order? (trace analysis)
3. Task completion: Does agent achieve the goal? (end-to-end scenarios)
4. Safety: Does agent stay within boundaries? (adversarial testing)
5. Efficiency: Steps taken, tokens used, latency (performance benchmarks)
```

**Key Services:** Bedrock Agent Evaluations, Bedrock Agent tracing, CloudWatch

---

#### Card 5.3: Troubleshooting Poor RAG Responses

**Diagnostic Flow:**
```
Poor response quality?
├─ Check retrieval: Are relevant chunks being retrieved?
│   ├─ No → Chunking problem (too large/small), embedding model mismatch
│   │       → Fix: adjust chunk size, try different embedding model, add metadata
│   └─ Yes → Check generation
├─ Check generation: Is FM using the context correctly?
│   ├─ Ignoring context → Prompt issue (context not emphasized)
│   │       → Fix: restructure prompt, add "answer ONLY from provided context"
│   ├─ Hallucinating beyond context → Grounding issue
│   │       → Fix: enable Guardrails grounding check, lower temperature
│   └─ Context window overflow → Too many chunks retrieved
│           → Fix: reduce top-K, enable reranking, compress chunks
└─ Check query: Is the user query well-formed?
    └─ Ambiguous → Add query expansion/decomposition
```

---

#### Card 5.4: Troubleshooting High Latency

**Diagnostic Flow:**
```
High latency?
├─ Where is time spent? (X-Ray trace)
│   ├─ Retrieval → OpenSearch slow
│   │   → Fix: optimize index (HNSW params), reduce top-K, add caching
│   ├─ FM inference → Model too large / long output
│   │   → Fix: use smaller model, limit max_tokens, enable streaming
│   ├─ Pre/post-processing → Lambda cold start or heavy processing
│   │   → Fix: provisioned concurrency, optimize code
│   └─ Network → VPC routing
│       → Fix: VPC endpoint in same AZ, check security group rules
└─ Consistent vs. spiky?
    ├─ Consistent → Architecture issue (above)
    └─ Spiky → Throttling → increase provisioned throughput or request limit increase
```

---

## Part 3: Condensed Reference by Domain

### Domain 1: FM Integration, Data Management, Compliance (31%)

**FM Selection & Configuration**
- **Bedrock** is the default for managed FM access — provides unified API across multiple model providers (Anthropic, Meta, Mistral, Amazon, Cohere, etc.) without managing infrastructure
- **SageMaker AI endpoints** are for self-managed models — use when you need custom containers, GPU control, or models not available in Bedrock
- **Cross-Region Inference** automatically routes requests to other regions when a region is at capacity — enable for production workloads to avoid throttling. This is different from manually deploying in multiple regions
- **Circuit breaker pattern** (via Step Functions): track consecutive failures; after threshold, route to fallback model or cached response to prevent cascading failures
- **Model customization options:**
  - *Continued pre-training*: extend model knowledge with domain corpus (e.g., medical literature). Most expensive, largest impact
  - *Fine-tuning*: adjust model behavior with labeled examples (input→output pairs). Good for style/format/task-specific behavior
  - *LoRA / adapters*: parameter-efficient fine-tuning — modify small number of parameters. Cheaper, faster, easier to version
  - *Prompt engineering*: no training needed. Always try this first before customization
- **SageMaker Model Registry**: version, catalog, and manage custom models with approval workflows. Integrates with CI/CD for automated deployment pipelines
- **Bedrock model access**: models must be explicitly enabled in your account. Use IAM to control which teams can enable/access which models

**Data Pipelines for FMs**
- **Glue Data Quality**: define rules (completeness, uniqueness, freshness) that data must pass before entering your RAG pipeline. Alert on quality degradation
- **Lambda functions**: lightweight custom transforms — normalize dates, clean HTML, extract text from proprietary formats
- **Multimodal pipeline**:
  - Audio → Amazon Transcribe → text for FM
  - Documents/images → Amazon Textract → structured text
  - Images → Bedrock multimodal models (Claude, Nova) → direct understanding without text extraction
- **Converse API**: Bedrock's model-agnostic API. Normalizes message format across all models — switch providers without changing code. Supports tool use, system prompts, multi-turn conversation out of the box
- **Input formatting matters**: each model has specific token limits, message formats, and system prompt handling. The Converse API abstracts this, but for InvokeModel you must match the model's native format

**Vector Stores**
- **Chunking strategies** determine how documents are split for embedding:
  - *Fixed-size* (e.g., 512 tokens with 20% overlap): simple, predictable. Works for uniform content. Risk: splits mid-paragraph
  - *Hierarchical*: preserves document structure (section → subsection → paragraph). Good for structured docs (manuals, policies). Enables parent-child retrieval
  - *Semantic*: splits at natural boundaries (topic shifts). Best quality but more expensive to compute. Use Bedrock's semantic chunking option
  - *Rule*: overlap between chunks (10-20%) helps capture concepts split across boundaries
- **Embedding model selection**:
  - Amazon Titan Text Embeddings V2: 256 / 512 / 1024 dimensions (configurable). Lower dimensions = cheaper storage + faster search with minor recall trade-off
  - Cohere Embed: 1024 dimensions, strong multilingual support
  - Match embedding model used at indexing time with query time — they must be the same model
- **Metadata framework**: attach structured metadata to each chunk — source document, page number, timestamp, author, department, access level. Enables filtered search (e.g., "only search HR documents from 2024")
- **Data sync strategies**:
  - Bedrock KB native sync: scheduled (daily/weekly) or on-demand. Handles diff detection, re-chunking, re-embedding automatically
  - Event-driven (custom): DynamoDB Streams / S3 Event Notifications → Lambda → re-embed + upsert to vector store. Near real-time freshness but more operational overhead

**Retrieval Mechanisms**
- **Semantic search** (vector similarity): finds contextually related content even if exact words differ. Core of RAG. Uses cosine similarity or dot product on embeddings
- **Keyword search** (BM25): traditional text matching. Still necessary for exact terms — product IDs, error codes, proper nouns that embeddings might not capture perfectly
- **Hybrid search**: combines both. Typically weighted (e.g., 0.7 semantic + 0.3 keyword). OpenSearch supports this natively with Neural plugin
- **Reranking**: after initial retrieval (top-K candidates), a cross-encoder model re-scores results for relevance. Much more accurate than bi-encoder similarity alone. Use Bedrock reranker models. Adds latency (50-200ms) but significantly improves precision
- **Query expansion**: use an LLM to rephrase/expand the user query before searching. "What's the return policy?" → also search "refund timeframe" + "how to return items". Improves recall
- **Query decomposition**: break complex multi-part queries into sub-queries, retrieve separately, then combine context. "Compare our Q1 and Q2 sales in Europe" → two retrievals + merge
- **Top-K and context window management**: retrieve enough chunks to cover the answer but not so many that irrelevant content confuses the FM. Typical: top-5 to top-10 chunks. Use reranking to reduce to top-3 most relevant

**Prompt Engineering**
- **System prompt components**: role definition ("You are a financial analyst..."), constraints ("Only use provided context"), output format ("Respond in JSON with fields..."), tone ("Professional, concise")
- **Few-shot examples**: include 2-5 input→output examples in the prompt to demonstrate desired format/behavior. More effective than lengthy instructions for formatting tasks
- **Chain-of-thought (CoT)**: "Think step by step before answering" forces reasoning. Improves accuracy on math, logic, multi-step problems. Costs more tokens
- **Prompt Flows (Bedrock)**: visual builder for multi-step prompt sequences. Supports: conditional branching (if sentiment negative → escalation path), iterative refinement (loop until quality threshold met), parallel execution (process multiple chunks simultaneously)
- **Prompt Management (Bedrock)**: centralized template store with parameterized variables (e.g., `{{customer_name}}`), version history, and the ability to reference by ID. Prevents prompt drift when multiple teams share prompts
- **Prompt governance**: CloudTrail logs which prompt versions were used when. CloudWatch tracks response quality per prompt version. Enables regression detection when prompts change

---

### Domain 2: Implementation and Integration (26%)

**Agentic AI**
- **Bedrock Agents**: fully managed agent orchestration. You define:
  - *Action groups*: tools the agent can call, defined via OpenAPI schema. Each action group backs to a Lambda function
  - *Knowledge bases*: RAG sources the agent can query for information
  - *Instructions*: natural language description of the agent's purpose and behavior rules
  - The agent automatically handles: task decomposition, tool selection, multi-turn conversation, error recovery
- **Amazon Bedrock AgentCore**: platform layer for building production agents at scale. Provides:
  - *Runtime*: host and execute agents with auto-scaling
  - *Memory*: short-term (session) and long-term (cross-session) memory
  - *Connectors*: pre-built integrations for common tools/services
  - *Identity*: per-user identity propagation for secure tool access
  - *Observability*: built-in tracing and metrics
- **Strands Agents SDK**: open-source Python SDK for building agents with full control. Choose your own LLM, define custom tool loops, implement any orchestration pattern (ReAct, plan-and-execute, tree-of-thought). Deploy on Lambda, ECS, or EC2
- **Agent Squad (AWS)**: framework for multi-agent collaboration. Define a supervisor that routes to specialized sub-agents. Each sub-agent has its own tools, instructions, and model
- **Model Context Protocol (MCP)**: open standard for agent-tool communication. MCP servers expose tools/resources; MCP clients (agents) discover and call them. Benefits: tool reuse across agents/frameworks, standardized discovery, consistent error handling
- **Agent safety essentials**:
  - IAM: each agent's Lambda/tools get minimum necessary permissions. Agent cannot access resources beyond its scope
  - Timeouts: Step Functions or Bedrock agent timeout prevents infinite loops
  - Max iterations: cap the number of reasoning steps
  - Human-in-the-loop: Step Functions callback pattern pauses for approval on high-risk actions
  - Guardrails: apply to both user input and agent output
  - Token budgets: set max token spend per invocation to prevent runaway costs

**Deployment**
- **On-demand inference** (Bedrock): pay per input/output token. No commitment. Best for: variable traffic, development, low-volume production. Risk: throttling under high load
- **Provisioned throughput** (Bedrock): reserve model capacity (measured in model units). Predictable latency and throughput. Best for: steady high-volume production. Requires commitment (1-month or 6-month terms)
- **Batch inference** (Bedrock): submit jobs to S3, results written to S3 asynchronously. ~50% cheaper than on-demand. Best for: offline processing (document summarization, data extraction). Not suitable for real-time
- **SageMaker endpoints**: host any model (Hugging Face, custom) on managed infrastructure. Options: real-time (always-on), serverless (scale to zero), async (for long-running inference). Use when: model not in Bedrock, need custom pre/post-processing, require specific GPU types
- **Model cascading implementation**: classifier (small model or rules) determines query complexity → routes to appropriate model tier. Example: regex catches FAQ → cached answer; simple query → Nova Micro; complex reasoning → Claude. Save 40-70% on inference costs

**Enterprise Integration**
- **API Gateway as GenAI facade**:
  - Authentication: Cognito/IAM authorizers ensure only authorized apps call your FM endpoints
  - Rate limiting: per-client throttling prevents any single consumer from exhausting model capacity
  - Request validation: JSON schema validation catches malformed requests before they reach your Lambda
  - Usage plans: allocate different rate limits and quotas per team/tier
- **EventBridge for event-driven AI**: trigger agent workflows from business events. Example: new support ticket created → EventBridge rule → Lambda → Bedrock agent classifies and routes. Loose coupling means AI components evolve independently
- **Step Functions for orchestration**: visual workflow engine. Key patterns for gen AI:
  - Sequential: pre-process → embed → retrieve → generate → post-process
  - Parallel: fan-out to multiple models, aggregate results
  - Error handling: catch model timeouts, retry with backoff, fallback to alternative
  - Map state: process array of documents in parallel with concurrency control
- **GenAI Gateway pattern**: centralized abstraction layer between consumers and FM providers. Benefits: switch models without changing consumer code; unified logging/metrics; cost allocation by consumer; enforce organization-wide guardrails. Implement with: API Gateway + Lambda + AppConfig (for routing rules)
- **CI/CD for GenAI**:
  - CodePipeline: orchestrate deploy stages (dev → staging → production)
  - Automated testing: run evaluation datasets against new prompt/model versions before promoting
  - Rollback: if quality metrics degrade, automatically revert to previous prompt version or model
  - Infrastructure as Code: CDK/CloudFormation for reproducible deployments of KB, agents, guardrails

**API Patterns**
- **Synchronous** (InvokeModel / Converse): request → wait → complete response. Simple. Use for: short responses, internal processing, batch pipelines
- **Streaming** (InvokeModelWithResponseStream / ConverseStream): response arrives token-by-token. Critical for chat UX — user sees text appearing immediately. Time-to-first-token typically 200-500ms vs. 2-10s for full response
- **Asynchronous**: decouple request from response. Pattern: client → API Gateway → SQS → Lambda → Bedrock → store result → notify client (webhook/polling). Use for: long-running generations, queue management, spike absorption
- **WebSocket** (API Gateway WebSocket API): persistent bidirectional connection. Best for: chat interfaces needing streaming + multi-turn state. Client sends messages, server streams tokens back on same connection

---

### Domain 3: AI Safety, Security, and Governance (20%)

**Input/Output Safety (Bedrock Guardrails)**
- **Content filters**: 6 categories (Hate, Insults, Sexual, Violence, Misconduct, Prompt Attack). Each configurable to LOW/MEDIUM/HIGH strength. Higher = more aggressive filtering (may increase false positives)
- **Denied topics**: define topics that should be completely blocked. Example: "Do not discuss competitor products" or "Do not provide legal advice." Uses FM-based classification to detect topic regardless of how it's phrased
- **Word filters**: exact-match blocking for specific words/phrases. Use for: profanity, competitor names, internal project codenames. Also includes a managed profanity list
- **Sensitive information filters**: detect and mask/block PII entities (SSN, email, phone, credit card, etc.) plus custom regex patterns (e.g., internal account ID format). Can mask (replace with `[MASKED]`) or block entirely
- **Contextual grounding check**: compares FM response against retrieved source documents. Scores how well the response is grounded in (supported by) the sources. Set a threshold — responses below it are blocked. Essential for RAG applications in regulated industries
- **Automated Reasoning checks**: validate FM responses against formal logical rules you define. Can detect logical inconsistencies, incorrect calculations, unsupported conclusions. Suggests corrections when violations found
- **Standard tier vs. Classic tier**: Standard extends detection into code elements (variable names, comments, string literals that might contain harmful content). Use Standard for code-generation use cases
- **ApplyGuardrail API**: evaluate content against guardrails WITHOUT invoking a model. Useful for: pre-screening user input before sending to FM, checking cached responses, validating external content

**Data Security**
- **VPC endpoints (PrivateLink)**: Bedrock and SageMaker support VPC endpoints. FM API calls never traverse the public internet. Critical for regulated workloads (HIPAA, PCI-DSS, financial services)
- **IAM granular access**: create role hierarchy:
  - *Evaluation role*: access to playground/sandbox models only. For experimentation
  - *General role*: access to approved production models. For standard applications
  - *Fine-tuned model role*: access to custom models trained on proprietary data. Restricted to specific teams
  - *Specialized role*: access to expensive/high-capability models. Budget-controlled
- **Lake Formation**: column-level and row-level security on data used for RAG. Ensure FM only retrieves data the requesting user is authorized to see
- **Encryption**:
  - At rest: S3 SSE-KMS for documents, vector store encryption (OpenSearch/Aurora native)
  - In transit: TLS 1.2+ for all API calls (enforced by default)
  - KMS customer-managed keys for invocation logs and model artifacts
- **Data retention**: configure S3 Lifecycle policies to automatically delete invocation logs after retention period. Important for: GDPR right-to-erasure, minimizing exposure window

**Governance & Compliance**
- **CloudTrail**: captures ALL Bedrock/SageMaker API calls as events. Who invoked which model, when, from where. Non-negotiable for audit readiness
- **Model invocation logging**: stores full request (prompt) and response content to S3 or CloudWatch Logs. Enable for: compliance audit, debugging, quality monitoring. Be cautious: logs may contain sensitive user data — apply encryption and access controls
- **SageMaker Model Cards**: structured documentation for each model — intended use, limitations, training data description, evaluation metrics, ethical considerations. Required for many compliance frameworks
- **Data lineage**: Glue Data Catalog tracks where data came from, how it was transformed, and where it ended up. Critical for: "which documents did this RAG response draw from?" and "was any training data from restricted sources?"
- **Compliance monitoring**: CloudWatch alarms on drift metrics. Example: if grounding score drops below threshold, alert. If a new model version produces different output distributions, flag for review

**Responsible AI**
- **Transparency**:
  - Bedrock agent traces: show complete reasoning chain — which tools were called, what information was retrieved, how decisions were made
  - Citations: Bedrock KB automatically returns source document references. Show these to users so they can verify claims
  - Confidence scoring: track and display model certainty signals
- **Fairness evaluation**:
  - Run same prompts with varied demographic references → compare response quality/tone
  - LLM-as-a-judge: have a separate model evaluate outputs for bias indicators
  - A/B test with diverse user groups and track satisfaction differences
- **OWASP Top 10 for LLM Applications** (key items):
  - LLM01: Prompt Injection — adversarial input that overrides system instructions
  - LLM02: Insecure Output Handling — using FM output unsanitized (e.g., as SQL)
  - LLM03: Training Data Poisoning — tainted training data leads to biased/harmful outputs
  - LLM04: Model Denial of Service — crafted inputs that cause excessive resource usage
  - LLM06: Sensitive Information Disclosure — FM reveals training data or PII
  - LLM08: Excessive Agency — agent takes actions beyond intended scope

---

### Domain 4: Operational Efficiency (12%)

**Cost Optimization**
- **Token efficiency strategies**:
  - Compress system prompts: remove redundant instructions, use concise phrasing
  - Limit output: set `max_tokens` to prevent verbose responses
  - Prune retrieved context: use reranking to send only top-3 most relevant chunks instead of top-10
  - Context window management: for multi-turn chat, summarize older messages instead of including full history
- **Model cascading** (detailed): classify query complexity → route to cheapest capable model
  - Implementation: small classifier model or rule-based (keyword/length) → routing Lambda → appropriate model
  - Savings: 40-70% because majority of queries are simple
  - Risk: misclassification sends complex query to weak model → poor response → potential retry on expensive model anyway
- **Prompt caching** (Bedrock): when system prompt is large and repeated across requests (e.g., same instructions for all users), Bedrock caches the KV pairs. Subsequent requests skip re-processing cached portion. Savings up to 90% on the cached token portion. Works best with: long system prompts, consistent instruction prefixes
- **Batch inference**: submit input file (JSONL in S3), Bedrock processes offline, writes results to S3. ~50% cheaper. Use for: nightly summarization jobs, weekly report generation, data enrichment pipelines. Latency: hours, not seconds
- **Provisioned throughput**: purchase dedicated capacity. Makes sense when: sustained traffic exceeds on-demand limits, need guaranteed latency SLA, predictable monthly cost preferred over variable. Break-even typically at 50-70% utilization
- **Semantic caching**: embed user queries → check similarity against cache of previous query→response pairs. If similarity > threshold (e.g., 0.95), return cached response without calling FM. Dramatically reduces costs for FAQ-like workloads. Challenge: cache invalidation when underlying data changes
- **Embedding cost optimization**: Titan V2 supports 256/512/1024 dimensions. Lower dimensions = less storage, faster similarity search, slightly lower recall. For many use cases, 512 dimensions is the sweet spot

**Performance Optimization**
- **Streaming** reduces perceived latency by 5-10x. Time-to-first-token (200-500ms) vs. time-to-complete-response (2-10s). Essential for chat interfaces. ConverseStream API handles this
- **Parallel processing**: when a task can be decomposed (e.g., summarize 10 documents), invoke FM in parallel via Step Functions Map state or concurrent Lambda invocations. Reduces wall-clock time linearly
- **Vector index optimization**:
  - HNSW parameters: `ef_construction` (higher = better recall at index time), `m` (connections per node — higher = better recall, more memory), `ef_search` (higher = better recall at query time, slower)
  - Sharding: distribute large indexes across multiple OpenSearch shards for parallel query
  - Warm storage: keep hot indexes in memory; archive old indexes to cold storage
- **Pre-computation**: for predictable queries (top FAQ, daily report), generate responses during off-peak and cache. Serve instantly at query time
- **Inference parameters tuning**:
  - `temperature`: 0 = deterministic (best for factual/consistent answers); 0.7-1.0 = creative (good for brainstorming, varied content)
  - `top_p`: nucleus sampling. 0.9 typical. Lower = more focused. Used together with or instead of temperature
  - `top_k`: limit vocabulary selection. Lower = more predictable. Less commonly tuned than temperature/top_p

**Monitoring & Observability**
- **Token metrics** (CloudWatch):
  - `InputTokenCount`, `OutputTokenCount` per model per request
  - Create custom metric for cost-per-request: (input_tokens × input_price) + (output_tokens × output_price)
  - Set alarms on: sudden token spikes (runaway agent), high output-to-input ratio (verbose responses)
- **Latency** (CloudWatch + X-Ray):
  - End-to-end: total time from user request to response
  - Component breakdown (X-Ray): retrieval time + inference time + pre/post-processing
  - Time-to-first-token: critical for streaming UX. Monitor p95
  - Set alarms on: p99 latency exceeding SLA, latency trending upward
- **Quality metrics** (custom CloudWatch metrics):
  - Grounding score from Guardrails: track percentage of responses passing grounding check
  - User feedback: thumbs up/down ratio, tracked over time
  - Hallucination rate: percentage of responses flagged by grounding check
  - Empty retrieval rate: percentage of queries where vector search returns no relevant results
- **Operational metrics**:
  - Error rate: 4xx (client errors — bad requests), 5xx (service errors — model failures)
  - Throttling rate: 429 responses indicating capacity limits hit
  - Model availability: track per-region, per-model availability
- **Business metrics**: task completion rate (agents), user satisfaction score, escalation rate, resolution rate
- **Dashboards**: combine operational + quality + business metrics on single CloudWatch dashboard. Include: real-time view, 7-day trend, cost burn rate

---

### Domain 5: Testing, Validation, Troubleshooting (11%)

**Evaluation Methods**
- **Bedrock Model Evaluation** supports three modes:
  - *Automatic*: metrics computed against reference answers — ROUGE-L (text overlap), cosine similarity (semantic), BERTScore (contextual similarity). Good for: comparing model versions quantitatively
  - *Human*: human reviewers score outputs on dimensions you define (helpfulness, accuracy, tone). Good for: subjective quality, nuanced assessment
  - *LLM-as-a-judge*: a separate FM scores outputs. Provides: scalability of automatic + nuance of human. Define evaluation criteria in judge prompt. No ground truth needed
- **RAG evaluation** (Bedrock): dedicated evaluation for knowledge base pipelines
  - Context relevance: are the retrieved chunks relevant to the query?
  - Faithfulness (grounding): is the generated response supported by the retrieved context?
  - Answer relevance: does the response actually answer the question?
  - Compare different KB configurations (chunk sizes, embedding models, retrieval strategies)
- **Agent evaluation** (Bedrock):
  - Task completion: did the agent achieve the intended goal?
  - Tool usage: did it call the right tools in a logical order?
  - Reasoning quality: are the intermediate steps sensible?
  - Efficiency: how many steps/tokens did it take?
- **A/B testing**: route percentage of production traffic to new model/prompt version. Compare metrics (quality, latency, cost) between variants. Use Bedrock model routing or custom Lambda-based routing

**Quality Assurance**
- **Golden datasets**: curated set of representative queries with expected answers/behaviors. Run against every new model/prompt version. Detect regressions immediately. Include: happy path, edge cases, adversarial inputs, multi-language
- **Canary deployments**: route 5-10% of traffic to new version. Monitor quality metrics. If degradation detected, automatically route back to previous version. Implement with: API Gateway canary or Lambda alias weighted routing
- **Automated quality gates**: in CI/CD pipeline, run evaluation dataset. If scores drop below threshold (e.g., faithfulness < 0.85), block deployment. Prevents quality regressions from reaching production
- **Continuous evaluation**: scheduled (daily/weekly) re-evaluation against golden dataset. Detects: model drift (provider model updates), data drift (vector store content changes), prompt decay (context changes make prompts less effective)

**Troubleshooting Patterns (Detailed)**
- **Context overflow** (response is truncated or incoherent mid-sentence):
  - Cause: too many chunks stuffed into context window
  - Diagnose: log total input token count; compare to model's context limit
  - Fix: reduce top-K; use reranking to keep only most relevant chunks; summarize context; use model with larger context window
- **Poor retrieval** (FM responds "I don't have information about that" despite data existing):
  - Cause: embedding mismatch, bad chunking, missing metadata
  - Diagnose: manually inspect retrieved chunks — are they relevant? Log retrieval scores
  - Fix: try different embedding model; adjust chunk size (too large = diluted; too small = no context); add metadata filters to narrow search; check if data sync is up-to-date
- **Hallucination** (FM confidently states incorrect information):
  - Cause: insufficient grounding, high temperature, weak instructions
  - Diagnose: enable Guardrails grounding check; compare response against retrieved context
  - Fix: add explicit instruction "only answer from provided context"; lower temperature toward 0; enable grounding check with strict threshold; add citations requirement
- **High latency** (slow responses):
  - Diagnose with X-Ray: identify which component is slow
  - If retrieval slow: optimize HNSW params, cache frequent queries, reduce top-K
  - If inference slow: use smaller model, reduce max_tokens, enable streaming
  - If pre-processing slow: Lambda cold start → use provisioned concurrency
  - If throttled: increase provisioned throughput, request quota increase, implement queuing
- **Agent infinite loop** (agent keeps calling tools without reaching conclusion):
  - Cause: ambiguous instructions, tool returning errors agent can't handle, circular reasoning
  - Diagnose: examine agent traces — look for repeated tool calls with same parameters
  - Fix: add explicit stopping conditions; set max iterations; improve tool error messages; clarify agent instructions about when to give up
- **Inconsistent outputs** (same input gives different answers each time):
  - Cause: high temperature, non-deterministic model behavior, prompt version mismatch
  - Fix: set temperature=0 for deterministic output; pin model version; pin prompt version via Prompt Management; use seed parameter if available
- **API errors** (throttling, timeouts, malformed requests):
  - 429 (ThrottlingException): implement exponential backoff with jitter; request limit increase; consider provisioned throughput
  - 408/timeout: reduce input size; increase client timeout; check if model is appropriate for request size
  - ValidationException: check request format matches model's expected schema; use Converse API for automatic format handling

---

## Quick Service Reference Card

| Capability | Primary Service | Alternative | Key Detail |
|-----------|----------------|-------------|------------|
| FM inference | Bedrock (Converse API) | SageMaker endpoints | Converse = model-agnostic; InvokeModel = model-specific |
| Managed RAG | Bedrock Knowledge Bases | Amazon Q Business | KB = developer-facing API; Q Business = end-user app with ACL |
| Vector search | OpenSearch Serverless | Aurora pgvector, Neptune | OpenSearch = hybrid search; Aurora = SQL teams; Neptune = graphs |
| Agents | Bedrock Agents / AgentCore | Strands SDK + Lambda | Bedrock = managed; Strands = full control; AgentCore = platform |
| Safety | Bedrock Guardrails | Custom (Comprehend + Lambda) | Guardrails = 6 filter types + grounding + automated reasoning |
| Orchestration | Step Functions | EventBridge + Lambda | Step Functions for stateful workflows; EventBridge for event routing |
| Monitoring | CloudWatch + X-Ray | Bedrock invocation logs | CloudWatch = metrics/alarms; X-Ray = distributed traces; Logs = content |
| Evaluation | Bedrock Model Evaluation | SageMaker Clarify | Bedrock = FM-specific (RAG, agent); Clarify = traditional ML bias/explain |
| PII detection | Comprehend / Bedrock Guardrails | Macie (S3 scanning) | Comprehend = real-time text; Guardrails = inline; Macie = stored data |
| Streaming | Bedrock ConverseStream | API Gateway WebSocket | ConverseStream = server→client; WebSocket = bidirectional |
| Prompt mgmt | Bedrock Prompt Management | S3 + custom versioning | Bedrock PM = templates + versions + parameterization |
| Cost tracking | CloudWatch + Cost Explorer | Custom tags + Budgets | Tag by team/app/model for allocation; Budget alerts for overruns |
| Audit | CloudTrail + invocation logs | Config rules | CloudTrail = API events; invocation logs = full content |
| Embeddings | Bedrock (Titan V2) | Cohere Embed / SageMaker | Titan V2 = configurable dimensions (256/512/1024) |
| Data processing | Bedrock Data Automation | Glue + Lambda | Data Automation = managed extraction/processing pipelines |

---

## Part 4: Documentation Resource List

> All links below are publicly accessible AWS documentation.
> Organized by exam domain for targeted study.

### Foundational Resources (Start Here)

| # | Resource | What It Covers |
|---|----------|---------------|
| 1 | [Well-Architected Generative AI Lens](https://docs.aws.amazon.com/wellarchitected/latest/generative-ai-lens/generative-ai-lens.html) | All 6 Well-Architected pillars applied to gen AI: operational excellence, security, reliability, performance, cost, sustainability |
| 2 | [Building an enterprise-ready gen AI platform on AWS](https://docs.aws.amazon.com/prescriptive-guidance/latest/strategy-enterprise-ready-gen-ai-platform/introduction.html) | 4-layer architecture: (1) infrastructure, (2) model selection/evaluation, (3) security/governance, (4) application patterns |
| 3 | [RAG options and architectures on AWS](https://docs.aws.amazon.com/prescriptive-guidance/latest/retrieval-augmented-generation-options/introduction.html) | Complete RAG guide: what is RAG, fully managed vs. custom, architecture comparisons, choosing an option |
| 4 | [Building serverless architectures for agentic AI on AWS](https://docs.aws.amazon.com/prescriptive-guidance/latest/agentic-ai-serverless/introduction.html) | Serverless + agents: Lambda, Step Functions, EventBridge, AgentCore patterns, business case |

### Domain 1: FM Integration, Data Management, Compliance

| # | Resource | What It Covers |
|---|----------|---------------|
| 5 | [Amazon Bedrock User Guide](https://docs.aws.amazon.com/bedrock/latest/userguide/what-is-bedrock.html) | Core Bedrock: model access, APIs, features, supported models |
| 6 | [Bedrock Model Evaluation](https://docs.aws.amazon.com/bedrock/latest/userguide/evaluation.html) | Automated + human evaluation, LLM-as-a-judge, RAG evaluation |
| 7 | [Bedrock Custom Models](https://docs.aws.amazon.com/bedrock/latest/userguide/custom-models.html) | Fine-tuning, continued pre-training, provisioned capacity for custom models |
| 8 | [Enterprise gen AI platform - Layer 2: Model selection](https://docs.aws.amazon.com/prescriptive-guidance/latest/strategy-enterprise-ready-gen-ai-platform/model.html) | Evaluation metrics (ROUGE-L, cosine, METEOR, LLM-as-a-judge), governance committee, model strategy |
| 9 | [Amazon Bedrock Knowledge Bases](https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base.html) | Managed RAG: ingestion, chunking, embedding, sync, RetrieveAndGenerate API, structured data stores |
| 10 | [How Bedrock Knowledge Bases Work](https://docs.aws.amazon.com/bedrock/latest/userguide/kb-how-it-works.html) | Chunking strategies, embedding process, indexing, vector store integration details |
| 11 | [Choosing an AWS vector database for RAG](https://docs.aws.amazon.com/prescriptive-guidance/latest/choosing-an-aws-vector-database-for-rag-use-cases/introduction.html) | OpenSearch vs. Aurora pgvector vs. Neptune vs. Bedrock managed — comparison framework |
| 12 | [Bedrock Prompt Management](https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-management.html) | Parameterized templates, versioning, prompt governance |
| 13 | [Bedrock Prompt Flows](https://docs.aws.amazon.com/bedrock/latest/userguide/flows.html) | Visual prompt chaining, conditional branching, multi-step orchestration |
| 14 | [Prompt engineering guidelines (Bedrock)](https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-engineering-guidelines.html) | Best practices: chain-of-thought, few-shot, structured outputs, system prompts |

### Domain 2: Implementation and Integration

| # | Resource | What It Covers |
|---|----------|---------------|
| 15 | [Amazon Bedrock Agents](https://docs.aws.amazon.com/bedrock/latest/userguide/agents.html) | Agent orchestration, action groups, tool use, knowledge base integration |
| 16 | [Amazon Bedrock AgentCore](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/what-is-bedrock-agentcore.html) | Agent runtime, memory (short + long term), connectors, multi-agent, MCP |
| 17 | [AgentCore Memory: long-term memory vs RAG](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/memory-ltm-rag.html) | When to use memory vs. RAG; session continuity vs. knowledge retrieval |
| 18 | [Bedrock Provisioned Throughput](https://docs.aws.amazon.com/bedrock/latest/userguide/prov-throughput.html) | Dedicated capacity, commitment terms, when to use vs. on-demand |
| 19 | [Bedrock API Reference](https://docs.aws.amazon.com/bedrock/latest/APIReference/welcome.html) | InvokeModel, Converse, ConverseStream, batch APIs — request/response formats |
| 20 | [SageMaker AI Model Deployment](https://docs.aws.amazon.com/sagemaker/latest/dg/deploy-model.html) | Real-time, serverless, async endpoints; custom containers; auto-scaling |
| 21 | [AWS Step Functions](https://docs.aws.amazon.com/step-functions/latest/dg/welcome.html) | Workflow orchestration, error handling, parallel execution, callbacks |
| 22 | [Amazon Q Business](https://docs.aws.amazon.com/amazonq/latest/qbusiness-ug/what-is.html) | Enterprise search + gen AI: data source connectors, user permissions, managed Q&A |
| 23 | [Bedrock Data Automation](https://docs.aws.amazon.com/bedrock/latest/userguide/data-automation.html) | Automated document/data processing workflows |
| 24 | [Bedrock Inference Types](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-types.html) | On-demand vs. provisioned vs. batch — comparison, pricing implications |

### Domain 3: AI Safety, Security, and Governance

| # | Resource | What It Covers |
|---|----------|---------------|
| 25 | [Amazon Bedrock Guardrails](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails.html) | All 6 filter types: content, denied topics, words, PII, grounding, automated reasoning |
| 26 | [Enterprise gen AI platform - Layer 3: Security](https://docs.aws.amazon.com/prescriptive-guidance/latest/strategy-enterprise-ready-gen-ai-platform/security.html) | IAM roles, PrivateLink, invocation logging, OWASP alignment, security scoping matrix |
| 27 | [Defense-in-depth for gen AI (OWASP Top 10)](https://aws.amazon.com/blogs/machine-learning/architect-defense-in-depth-security-for-generative-ai-applications-using-the-owasp-top-10-for-llms/) | Layered security architecture mapped to LLM-specific threats [blog] |
| 28 | [Generative AI Security Scoping Matrix](https://aws.amazon.com/blogs/security/securing-generative-ai-an-introduction-to-the-generative-ai-security-scoping-matrix/) | Framework for classifying security requirements by deployment scope [blog] |
| 29 | [Bedrock Model Invocation Logging](https://docs.aws.amazon.com/bedrock/latest/userguide/model-invocation-logging.html) | Log full prompts/responses to S3 or CloudWatch for compliance/audit |
| 30 | [Bedrock CloudTrail Integration](https://docs.aws.amazon.com/bedrock/latest/userguide/logging-using-cloudtrail.html) | API-level audit trail for all Bedrock operations |
| 31 | [SageMaker Model Cards](https://docs.aws.amazon.com/sagemaker/latest/dg/model-cards.html) | Structured model documentation: purpose, limitations, evaluation results, ethics |
| 32 | [Amazon Comprehend PII Detection](https://docs.aws.amazon.com/comprehend/latest/dg/how-pii.html) | Real-time PII entity detection and redaction |
| 33 | [Amazon Macie](https://docs.aws.amazon.com/macie/latest/user/what-is-macie.html) | ML-powered sensitive data discovery in S3 buckets |

### Domain 4: Operational Efficiency and Optimization

| # | Resource | What It Covers |
|---|----------|---------------|
| 34 | [Well-Architected Gen AI Lens - Cost Optimization](https://docs.aws.amazon.com/wellarchitected/latest/generative-ai-lens/cost-optimization.html) | Model selection for cost, token efficiency, agent workflow optimization |
| 35 | [Well-Architected Gen AI Lens - Performance Efficiency](https://docs.aws.amazon.com/wellarchitected/latest/generative-ai-lens/performance-efficiency.html) | Latency optimization, compute selection, retrieval performance tuning |
| 36 | [Bedrock Prompt Caching](https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-caching.html) | Cache repeated prompt prefixes to reduce cost and latency |
| 37 | [Bedrock CloudWatch Metrics](https://docs.aws.amazon.com/bedrock/latest/userguide/monitoring-cw.html) | Available metrics: token usage, latency, throttling, error rates |
| 38 | [AWS X-Ray](https://docs.aws.amazon.com/xray/latest/devguide/aws-xray.html) | Distributed tracing across gen AI pipeline components |
| 39 | [CloudWatch Logs Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AnalyzingLogData.html) | Query and analyze prompt/response logs at scale |

### Domain 5: Testing, Validation, and Troubleshooting

| # | Resource | What It Covers |
|---|----------|---------------|
| 40 | [Bedrock Model Evaluation (detailed)](https://docs.aws.amazon.com/bedrock/latest/userguide/evaluation.html) | Automatic metrics, human evaluation, custom evaluation criteria |
| 41 | [Evaluate RAG Sources](https://docs.aws.amazon.com/bedrock/latest/userguide/evaluation-kb.html) | RAG-specific metrics: context relevance, faithfulness, answer quality |
| 42 | [LLM-as-a-Judge Evaluation](https://docs.aws.amazon.com/bedrock/latest/userguide/evaluation-judge.html) | Use FM to evaluate FM outputs — no ground truth needed |
| 43 | [Bedrock Agent Tracing](https://docs.aws.amazon.com/bedrock/latest/userguide/trace-events.html) | Step-by-step reasoning traces for debugging agent behavior |
| 44 | [Test and Troubleshoot Agents](https://docs.aws.amazon.com/bedrock/latest/userguide/agents-test.html) | Agent testing workflows and common issues |
| 45 | [Well-Architected Gen AI Lens - Operational Excellence](https://docs.aws.amazon.com/wellarchitected/latest/generative-ai-lens/operational-excellence.html) | Output quality monitoring, lifecycle management, traceability |

### Supporting Services (Frequently Tested)

| # | Resource | Exam Relevance |
|---|----------|---------------|
| 46 | [AWS Lambda](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html) | Event-driven AI, pre/post-processing, MCP servers, action group handlers |
| 47 | [API Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/welcome.html) | GenAI gateway facade, rate limiting, auth, WebSocket streaming |
| 48 | [Amazon EventBridge](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-what-is.html) | Event-driven agent triggers, loose-coupled AI workflows |
| 49 | [OpenSearch Service (vector search)](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/knn.html) | k-NN plugin, HNSW/IVF indexes, hybrid search, custom vector stores |
| 50 | [Amazon DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Introduction.html) | Conversation history, session state, metadata, caching layer |
| 51 | [AWS Glue Data Quality](https://docs.aws.amazon.com/glue/latest/dg/glue-data-quality.html) | Data validation rules for RAG ingestion pipelines |
| 52 | [SageMaker Clarify](https://docs.aws.amazon.com/sagemaker/latest/dg/clarify-configure-processing-jobs.html) | Bias detection, feature importance, model explainability |

### Suggested Study Order

```
Week 1: Foundation (Resources 1-4)
  Read the enterprise platform guide and RAG architectures guide end-to-end.
  Skim the Gen AI Lens for structure — return to specific pillars later.

Week 2: Core Bedrock (Resources 5-14)
  Focus on: Knowledge Bases, Prompt Management, model evaluation.
  Hands-on: build a simple KB, test chunking strategies, try Prompt Flows.

Week 3: Agents & Integration (Resources 15-24)
  Focus on: Agents action groups, AgentCore memory, Step Functions patterns.
  Hands-on: build an agent with 2 action groups, implement streaming.

Week 4: Security & Governance (Resources 25-33)
  Focus on: Guardrails configuration, defense-in-depth layers.
  Read both blog posts (OWASP + Security Scoping Matrix).

Week 5: Operations & Testing (Resources 34-45)
  Focus on: cost optimization levers, evaluation methods, troubleshooting.
  Hands-on: run a model evaluation, examine agent traces.
```

---

## Part 5: From Theory to Practice — Specializing an LLM for Your Stack

> This section bridges exam/architecture knowledge to hands-on implementation.
> It demonstrates how RAG, embeddings, MCP, fine-tuning, and model customization
> concepts apply when building a practical coding assistant for your tech stack.

### The Problem

You want to tell a coding assistant "Build a dialog to accept user input backed by a REST endpoint" and have it produce idiomatic code using your exact stack (e.g., htmx 4.0 + DaisyUI + Tailwind + Go) — including APIs released after the model's knowledge cutoff.

### Approaches Compared

| Approach | Labeled Data Needed? | Handles Post-Cutoff? | Effort | Best For | Architecture Concept |
|---|---|---|---|---|---|
| RAG | No | Yes | Medium | Accurate doc lookup on demand | Domain 1: vector stores, chunking, retrieval |
| MCP Server | No | Yes | Medium | On-demand retrieval without context bloat | Domain 2: agent tool integration |
| Steering/Skills Files | No | Partially (manual) | Low | Conventions, patterns, stack preferences | Domain 1: system prompts, prompt engineering |
| Continued Pre-Training | No (raw text) | Yes | High | Baking knowledge into weights (org-scale) | Domain 1: FM customization |
| Fine-Tuning (SFT) | Yes (Q&A pairs) | Yes | High | Style + behavior shaping | Domain 1: FM customization |
| Distillation | Generated pairs | Yes | High | Small local model with baked-in knowledge | Domain 2: model cascading, deployment |

### Recommended Layered Setup

Priority order — each layer adds value and maps to exam concepts:

**Layer 1: Steering / Skills Files** (= System Prompt engineering)
```markdown
## Stack Conventions
- Frontend: htmx 4.0 + DaisyUI, Backend: Go with chi router
- Return HTML fragments, not JSON. Use hx-get/hx-post for interactions.
- Use `hx-on:event` syntax (not `hx-on="event: ..."`)
```
This is prompt engineering in practice — encoding constraints and output format.

**Layer 2: Existing Code as Context** (= Few-shot prompting)
The model reads your existing code and matches patterns. A few well-written examples of your conventions are worth more than pages of instructions.

**Layer 3: MCP Server for Documentation** (= RAG + Agent tool use)
```
Your docs (HTML/PDF/MD) → Chunked + embedded → Vector database
                                                      ↓
MCP Server queries vector DB via search tools
                                                      ↓
AI assistant calls tools when needed → gets current API info
```

This is a concrete implementation of:
- **Chunking** (Domain 1 Task 1.5) — splitting docs for embedding
- **Embedding models** (Domain 1 Task 1.5) — converting text to vectors
- **Vector search** (Domain 1 Task 1.4) — finding relevant chunks
- **MCP protocol** (Domain 2 Task 2.1) — standardized agent-tool interface
- **On-demand retrieval** — lean context, tools called only when needed

**Example MCP Server (Python, using FastMCP):**
```python
from mcp.server.fastmcp import FastMCP
import json

mcp = FastMCP("stack-docs")

@mcp.tool()
def search_htmx_docs(query: str) -> str:
    """Search htmx 4.0 beta documentation."""
    results = vector_store.search("htmx", query, top_k=5)
    return json.dumps(results)

@mcp.tool()
def search_go_docs(package: str, symbol: str = "") -> str:
    """Search Go standard library or project dependency docs."""
    results = vector_store.search("go", f"{package} {symbol}", top_k=5)
    return json.dumps(results)

if __name__ == "__main__":
    mcp.run()
```

**Deployment mapping to exam patterns:**
| Tool Characteristics | Deploy On | Exam Concept |
|---|---|---|
| Stateless, lightweight, fast responses | Lambda | Card 2.5: MCP on Lambda |
| Stateful, persistent connections | ECS on Fargate | Card 2.5: MCP on ECS |
| Standard database access | AgentCore prebuilt MCP servers | AgentCore connectors |

### Vector Database for Local Development

| Option | Notes | AWS Equivalent |
|---|---|---|
| ChromaDB | Python-native, simple API | Bedrock managed store |
| LanceDB | Rust-based, fast, no server | — |
| SQLite-vec | Single-file, minimal deps | — |
| FAISS | Facebook's library, very fast | OpenSearch k-NN engine |

**The embedding model rule** (= embedding drift from Domain 5 troubleshooting):
The model used to embed documents at index time MUST be the same model used to embed queries at search time. Switching models = re-index everything. This is exactly the "embedding drift" scenario from troubleshooting Card 5.3.

### When Training Is Needed vs. Not

For well-known stacks with public documentation:
```
Steering file (conventions + breaking changes)    → System prompt
    + Existing code (patterns by example)         → Few-shot
    + MCP server (current docs on demand)         → RAG/tool use
    = Specialized assistant, NO training required
```

When training makes sense:

| Scenario | Approach | Why RAG Alone Fails |
|---|---|---|
| Autocomplete / inline suggestions (latency-critical) | Distill into small local model | RAG adds 200-500ms per tool call; too slow for keystroke-level suggestions |
| Proprietary internal framework with no public docs | Fine-tune or distill | No external source to retrieve from |
| Offline / air-gapped environment | Distilled model via Ollama | Can't call external APIs or cloud services |
| Organization-wide, thousands of developers | Continued pre-training + fine-tuning | Scale justifies the investment |

### Distillation Pipeline (maps to Domain 1: model customization)

```
1. Frontier model (Claude) + RAG over your docs → generate Q&A pairs
2. Fine-tune small model (Llama 8B) on those pairs using LoRA
3. Export to GGUF → deploy on Ollama (or SageMaker endpoint)
```

This maps directly to:
- **LoRA/adapters** (Domain 1 Task 1.2) — parameter-efficient fine-tuning
- **Knowledge distillation** (study-notes Section 3) — teacher→student model compression
- **SageMaker deployment** (Domain 2 Task 2.2) — custom model hosting

### Key Takeaway

Every concept in the exam has a direct practical application:

| Exam Concept | Practical Use |
|---|---|
| Chunking strategies | How you split your framework docs for indexing |
| Embedding models | What converts your docs to searchable vectors |
| Vector databases | Where those vectors live (local or cloud) |
| MCP protocol | How your coding assistant calls your doc search |
| System prompts | Your steering file with stack conventions |
| Model cascading | Use small model for autocomplete, large for generation |
| Prompt caching | Same system prompt across all requests to your assistant |
| Grounding | Ensuring code suggestions come from actual documentation |

### References

- [The Illustrated Transformer](https://jalammar.github.io/illustrated-transformer/) — Visual walkthrough of transformer architecture
- [3Blue1Brown - Transformers](https://www.3blue1brown.com/lessons/gpt) — Animated series on attention and GPT
- [A Visual Guide to LLMs](https://awesomeneuron.substack.com/p/a-visual-guide-to-llms-part-1) — Illustrated tokenization, embeddings, attention
- [StatQuest Illustrated Guide to Neural Networks](https://www.amazon.com/dp/B0DRS71QVQ) — From basics through transformers with PyTorch
