# Operations, Monitoring & Backup Release Checklist

> **Applicability:** Run this checklist for all deployable services, automation scripts, plugins, scheduled jobs, and applications prior to release.
>
> **Severity Key:** Unmet `[BLOCK]` items risk unrecoverable data loss, silent production outages, or broken rollbacks and must mark the domain `BLOCK`. Unmet `[WARN]` items mark the domain `WARN`.

## Checklist Items

- [ ] **[BLOCK] Environment Configuration & Secret Separation:** All environment-specific URLs, credentials, and feature flags are externalized via environment variables or untracked config files, with a complete `.env.example` or configuration template documented.
- [ ] **[BLOCK] Tested Rollback / Restore Path:** A documented and tested mechanism exists to roll back a failed release or package update to the previous known-good version (e.g., atomic backup/restore, immutable container tag, or reversible migration).
- [ ] **[BLOCK] Database Migration & Data Backup Safety:** If the release modifies persistent data schemas or user files, backups are taken automatically before mutation and migrations are non-destructive or backward-compatible.
- [ ] **[BLOCK] Idempotent Install, Startup & Retry Behavior:** Running the installer, startup script, or scheduled job twice in a row succeeds cleanly without corrupting state, duplicating records, or overwriting user customizations.
- [ ] **[BLOCK] Safe Error Handling Without Secret Leakage:** Unhandled exceptions, network failures, and non-zero exit codes return clear diagnostic messages and appropriate exit/HTTP status codes without exposing stack traces or credentials to end users.
- [ ] **[WARN] Health Check / Readiness Verification Command:** Services expose a `/health` or `/ready` endpoint (or CLI/plugins provide a deterministic validation script like `Validate-Repo.ps1`) to verify live operational integrity immediately after deployment.
- [ ] **[WARN] Structured Logging & Error Monitoring:** Critical operations, background jobs, and failure paths emit structured logs or error telemetry so production incidents can be diagnosed without attaching a debugger.
- [ ] **[WARN] Graceful Shutdown & Partial-File Cleanup:** Processes handle termination signals (`SIGTERM`/`SIGINT`) or mid-run failures cleanly, removing temporary `.tmp` / `.partial` directories so subsequent runs are not wedged.
- [ ] **[WARN] Rate Limiting & Quota Protection:** Public endpoints, background polling jobs, and external API callers enforce rate limits or time gates (e.g., weekly schedule gates) to prevent runaway resource or token consumption.
- [ ] **[WARN] Release Notes / `CHANGELOG.md` Updated:** Version numbers (`plugin.json`, `package.json`, etc.) and `CHANGELOG.md` document breaking changes, new features, and upgrade instructions for this release.
