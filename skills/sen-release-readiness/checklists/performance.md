# Performance & Bundle Size Release Checklist

> **Applicability:** Run this checklist for all applications, APIs, scripts, plugins, and libraries prior to release.
>
> **Severity Key:** Unmet `[BLOCK]` items cause severe latency, memory leaks, quota blowups, or unresponsive UI and must mark the domain `BLOCK`. Unmet `[WARN]` items mark the domain `WARN`.

## Checklist Items

- [ ] **[BLOCK] No Unbounded Queries or Unpaginated Endpoints:** Database queries and list API endpoints enforce pagination or hard result limits (`LIMIT`), and core filter/join columns are backed by appropriate database indexes.
- [ ] **[BLOCK] No N+1 Query Loops on Hot Paths:** Request handlers, batch scripts, and rendering loops do not execute per-item network or database round-trips inside loops when batching or eager loading is available.
- [ ] **[BLOCK] External Network Calls Have Explicit Timeouts:** All outbound HTTP, RPC, or subprocess calls to external services specify explicit connection and read timeouts so a hung upstream cannot stall workers indefinitely.
- [ ] **[BLOCK] No Memory Leaks or Unclosed Resource Handles:** Event listeners, timers, file streams, database connections, and temporary directories are properly cleaned up on teardown and error paths.
- [ ] **[BLOCK] Production Build & Asset Optimization Enabled:** Production builds minify/tree-shake bundles (or respect byte/token budgets for AI rules and skills) and do not ship development debuggers or unminified vendor debug payloads.
- [ ] **[WARN] Bundle Size & Initial Load Budget Checked:** Client-side JavaScript/CSS bundles and heavy third-party libraries are lazy-loaded or code-split where appropriate so initial load size stays within project budgets.
- [ ] **[WARN] Image & Media Asset Compression:** Static images, logos, and media files use modern compressed formats (`WebP`, `AVIF`, optimized `SVG`/`PNG`) with explicit `width` and `height` attributes to prevent layout shifts (CLS).
- [ ] **[WARN] Caching Headers & Idempotent Reuse:** Static assets and expensive read-mostly computations use appropriate caching (`Cache-Control`, ETags, memoization, or scheduled gates) to avoid redundant work.
- [ ] **[WARN] Graceful Degradation on Slow Networks or Large Inputs:** UI views show loading states, skeletons, or progress indicators for operations taking longer than `300ms`, and large lists use pagination or virtualization.
