---
layout: ../layouts/GistLayout.astro
---

# AWS Generative AI Architecture Quick Reference

> Aligned with AWS Certified Generative AI Developer - Professional (AIP-C01) domains.
> Focused on real-world architectural decisions and patterns.

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

### 1.2b k-NN Algorithms & Index Methods (OpenSearch)

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

### 1.3 Foundation Model Selection

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

### 1.4 Agent Architecture Selection

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

---

### 1.5 Security & Guardrails Selection

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

### 1.6 Cost Optimization Decisions

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
┌─────────────────────────────────────────────────────┐
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
└─────────────────────────────────────────────────────┘
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
