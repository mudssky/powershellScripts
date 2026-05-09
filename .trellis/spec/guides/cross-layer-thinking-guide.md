# Cross-Layer Thinking Guide

> **Purpose**: Think through data flow across layers before implementing.

---

## The Problem

**Most bugs happen at layer boundaries**, not within layers.

Common cross-layer bugs:
- API returns format A, frontend expects format B
- Database stores X, service transforms to Y, but loses data
- Multiple layers implement the same logic differently

---

## Before Implementing Cross-Layer Features

### Step 1: Map the Data Flow

Draw out how data moves:

```
Source → Transform → Store → Retrieve → Transform → Display
```

For each arrow, ask:
- What format is the data in?
- What could go wrong?
- Who is responsible for validation?

### Step 2: Identify Boundaries

| Boundary | Common Issues |
|----------|---------------|
| API ↔ Service | Type mismatches, missing fields |
| Service ↔ Database | Format conversions, null handling |
| Backend ↔ Frontend | Serialization, date formats |
| Component ↔ Component | Props shape changes |

### Step 3: Define Contracts

For each boundary:
- What is the exact input format?
- What is the exact output format?
- What errors can occur?

---

## Common Cross-Layer Mistakes

### Mistake 1: Implicit Format Assumptions

**Bad**: Assuming date format without checking

**Good**: Explicit format conversion at boundaries

### Mistake 2: Scattered Validation

**Bad**: Validating the same thing in multiple layers

**Good**: Validate once at the entry point

### Mistake 3: Leaky Abstractions

**Bad**: Component knows about database schema

**Good**: Each layer only knows its neighbors

### Mistake 4: Hook Stage Assumptions

**Bad**: 根据 hook 名称推断它能修改真实请求，例如把 logging pre-call 当成 provider 请求构造前的改写点。

**Good**: 先确认 hook 在完整生命周期中的位置，并验证它修改的是下游实际消费的数据结构，而不是日志副本、已序列化后的副本或另一个进程里的状态。

When lifecycle hooks cross layers, map the flow explicitly:

```
Proxy request → Router deployment selection → pre-deployment hook → provider transform/sign → logging hook → HTTP send
```

For each hook, ask:
- Is the target deployment/provider already known?
- Has the request body been transformed or serialized yet?
- Does this hook return modified data, mutate a live reference, or only log a snapshot?
- How can runtime state be checked from the serving process rather than a fresh local process?

---

## Checklist for Cross-Layer Features

Before implementation:
- [ ] Mapped the complete data flow
- [ ] Identified all layer boundaries
- [ ] Defined format at each boundary
- [ ] Decided where validation happens

After implementation:
- [ ] Tested with edge cases (null, empty, invalid)
- [ ] Verified error handling at each boundary
- [ ] Checked data survives round-trip
- [ ] For lifecycle hooks, verified the hook stage with source or docs and tested the exact structure consumed by the downstream layer

---

## When to Create Flow Documentation

Create detailed flow docs when:
- Feature spans 3+ layers
- Multiple teams are involved
- Data format is complex
- Feature has caused bugs before
