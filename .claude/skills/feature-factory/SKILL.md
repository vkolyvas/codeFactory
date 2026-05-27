---
name: feature-factory
description: Use this skill when the user asks to build, ship, or implement a feature end to end. Runs the full chain with parallel reviewer fan-out after builds, then validation. Triggers on: "build a feature", "ship a feature", "run the factory", "feature factory", "/feature-factory".
---

## Mode Selection

Before running the chain, determine the execution mode:

- **full-feature** (default): researcher → story → spec → backend → [security | architecture | migration? | docs] → frontend → test → validate
- **hotfix**: researcher → backend → [security | architecture | migration?] → test → validate (skips story and spec)
- **backend-only**: researcher → story → spec → backend → [security | architecture | migration?] → test → validate (skips frontend)
- **frontend-only**: researcher → story → spec → frontend → test → validate (API contract must pre-exist)
- **docs-only**: researcher → story → docs → validate

Ask the user to confirm the mode if ambiguous.

## Lane Model

Agents belong to one of four lanes:

| Lane | Agents | May Edit | Blocking |
|------|--------|----------|----------|
| A — Builders | backend-builder, frontend-builder | Yes (source) | Yes |
| B — Reviewers | security-reviewer, architecture-reviewer, migration-reviewer | No | Yes |
| C — Verifiers | test-verifier, implementation-validator | No (tests only) | Yes |
| D — Docs | docs-writer | Yes (docs only) | No (non-blocking) |

Only add an agent when: (1) the task repeats often, (2) deterministic automation is insufficient, (3) output materially changes merge quality.

## Run-Scoped Artifact Root

At chain start:

```
context_sha=$(git rev-parse HEAD)
artifact_root=$(mktemp -d "/tmp/factory/${context_sha}-XXXXXX")
```

All artifacts live under `$artifact_root/`.

## Manifest File

At chain start, write `$artifact_root/manifest.yaml`:

```yaml
run_id: "{basename of artifact_root}"
context_sha: "{context_sha}"
started_at: "{ISO8601 timestamp}"
mode: "{full-feature|hotfix|backend-only|frontend-only|docs-only}"
status: running

artifacts:
  researcher-findings: pending
  user-story: pending
  technical-brief: pending
  api-contract: pending
  architecture-contract: pending
  backend-summary: pending
  security-findings: pending
  architecture-findings: pending
  migration-findings: not_applicable
  docs-report: not_applicable
  frontend-summary: pending
  acceptance-test-report: pending

phase: initialized
```

After each phase: update `manifest.yaml` artifacts entry and `phase` field.

On crash: read manifest → find incomplete phase → resume from there.

## Architecture Contract (P13)

At chain start, before invoking any agent, generate the run-scoped **`declared`** architecture contract at `$artifact_root/architecture-contract.yaml`:

> **Important:** This file declares the INTENDED architecture — what boundaries SHOULD exist — not what currently exists in the codebase. It is not derived by inspecting code. Enterprise codebases have accumulated chaos; you must not encode that as truth. The spec-writer owns this artifact.

**Generation method:**
1. Read `CLAUDE.md` for explicit architectural rules (layers, ownership, don't-do list).
2. If the codebase has existing architecture (e.g., an established `docs/adr/` with ADRs, or existing layer structure), read those and treat them as declared ground truth.
3. If no existing declared architecture exists, infer ONLY the physical directory structure as a starting point — then annotate each layer with its intended semantic role based on directory name semantics.
4. Always write explicit `declared_at: "{ISO8601}"` field — distinguishes from generated/observed contracts.

**Output structure:**

```yaml
schema_version: 1
context_sha: "{context_sha}"
generated_at: "{ISO8601}"          # This is the DECLARED contract generation time
kind: declared                      # distinguishing label
declared_at: "{ISO8601}"            # when this was authored

layers:
  api:
    may_import:
      - services
      - schemas
      - use-cases
  services:
    may_import:
      - repositories
      - domain
      - schemas
  repositories:
    may_import:
      - db

forbidden:
  - from: api
    to: db
  - from: components
    to: prisma
  - from: services
    to: api

ownership:
  "src/api/**":
    lane: backend-builder
  "src/services/**":
    lane: backend-builder
  "src/components/**":
    lane: frontend-builder
  "app/components/**":
    lane: frontend-builder

escape_hatches:                     # new: controlled cross-boundary allowlist
  - pattern: "shared/**"            # shared utilities may reach domain
    allowed_calls:
      - cross_domain_transaction
      - performance_critical_path
    requires:
      - documented_reason           # inline code comment
      - override_annotation         # special comment in source file

dependency_tool: depcruise
dependency_config: .dependency-cruiser.yaml
```

The declaration is written once at chain start. The **observed** architecture is generated separately by the architecture-reviewer during fan-out (not written to this file — it goes to `observed-dependencies.json` in the artifact root so the two can be diffed).

## Artifact File Map

| Artifact | Written by | Read by |
|---|---|---|
| `$artifact_root/researcher-findings.md` | codebase-researcher | story-writer, spec-writer, builders |
| `$artifact_root/user-story.md` | story-writer | spec-writer, test-verifier, validator |
| `$artifact_root/technical-brief.md` | spec-writer | builders, reviewers, verifier |
| `$artifact_root/api-contract.yaml` | backend-builder | frontend-builder, test-verifier |
| `$artifact_root/architecture-contract.yaml` | orchestrator (generated) | architecture-reviewer, builders |
| `$artifact_root/backend-summary.md` | backend-builder | reviewers, frontend-builder |
| `$artifact_root/security-findings.md` | security-reviewer | validator |
| `$artifact_root/architecture-findings.md` | architecture-reviewer | validator |
| `$artifact_root/migration-findings.md` | migration-reviewer | validator |
| `$artifact_root/docs-report.md` | docs-writer | validator |
| `$artifact_root/frontend-summary.md` | frontend-builder | verifier |
| `$artifact_root/acceptance-test-report.md` | test-verifier | validator |
| `$artifact_root/manifest.yaml` | orchestrator | orchestrator, resume |

## Context SHA Pinning

`context_sha` captured at chain start. Every agent validates `git rev-parse HEAD` before executing. If SHA drifts: abort, surface conflict, let user decide.

## Contract Validation Gate

After backend-builder writes `api-contract.yaml` and before fan-out:

1. Run yamllint on `$artifact_root/api-contract.yaml` if available; skip if not installed.
2. If yamllint fails: abort, do not start reviewers or frontend-builder.
3. frontend-builder validates `schema_version` and `context_sha` before consuming.

## Dependency Boundary Check

After backend-builder writes implementation (before fan-out):

Run dependency-cruiser if available:
```bash
npx depcruise src --config .dependency-cruiser.yaml --validate 2>/dev/null
```
If violations found: treat as Critical architecture findings, include in `architecture-findings.md`.
If depcruise not available: architecture-reviewer will do grep-based checks instead.

## Contract Change Reconciliation

If backend-builder re-runs after validator feedback:
1. Regenerate `api-contract.yaml` with new `generated_at`.
2. Invalidate all downstream work (frontend, reviewers).
3. Re-run the full fan-out from step 12.

## Process (full-feature mode)

1. Capture `context_sha`. Create `artifact_root`. Write `manifest.yaml`.

2. Generate `$artifact_root/architecture-contract.yaml` — the **declared** architecture contract. This is INTENTION, not observation. Do not derive from inspecting existing code — that encodes legacy chaos. Read CLAUDE.md for explicit rules; treat existing ADRs or established structure as ground truth. Write `kind: declared` + `declared_at` timestamp. Update manifest.

3. Invoke **codebase-researcher**. Write `$artifact_root/researcher-findings.md`. Update manifest.

4. Invoke **story-writer**. Read findings. Write `$artifact_root/user-story.md`. Update manifest.

5. Show story to user. Ask: approved / changes / reject.
   - Approved → continue.
   - Changes → re-invoke story-writer. Repeat.
   - Rejected → stop. Do NOT cleanup. User may inspect artifacts.

6. Validate `context_sha`. If drift → abort.

7. Invoke **spec-writer**. Write `$artifact_root/technical-brief.md`. Update manifest.

8. Show brief to user. Ask: approved / changes / reject.
   - Approved → continue.
   - Changes → re-invoke spec-writer. Repeat.
   - Rejected → stop. Keep approved story. Do NOT cleanup.

9. Validate `context_sha`. If drift → abort.

10. Invoke **backend-builder**. Validate SHA. Write implementation. Write `$artifact_root/api-contract.yaml` and `$artifact_root/backend-summary.md`. Update manifest. Wait.

11. **Contract gate**: yamllint on `api-contract.yaml`. Fail on error.

12. **Dependency check**: run `depcruise` if available. If violations found, write to `architecture-findings.md` as Critical.

13. **Fan-out (parallel)** — all four run simultaneously:
    - Invoke **security-reviewer**. Read brief + implementation. Write `$artifact_root/security-findings.md`. Update manifest: `security-findings: present`.
    - Invoke **architecture-reviewer**. Read `architecture-contract.yaml` + implementation. Write `$artifact_root/architecture-findings.md`. Update manifest: `architecture-findings: present`.
    - Invoke **migration-reviewer** — ONLY if brief or changed files include `prisma/`, `migrations/`, or `schema.prisma`. If not applicable: write `migration-findings: not_applicable` to manifest and skip. Update manifest.
    - Invoke **docs-writer** — non-blocking. Read summaries. Write `$artifact_root/docs-report.md`. Update manifest. **Do not block chain on docs.**
    Wait for all four to complete.

14. Invoke **frontend-builder**. Read `api-contract.yaml` (mandatory, not optional). Validate `schema_version` + `context_sha`. Write `$artifact_root/frontend-summary.md`. Update manifest. Wait.

15. Validate `context_sha`. If drift → abort and surface conflict.

16. Invoke **test-verifier**. Read story, brief, `api-contract.yaml`, both summaries. Write `$artifact_root/acceptance-test-report.md`. Update manifest.

17. Invoke **implementation-validator**. Read all artifacts. Report findings grouped by severity, including security, architecture, and migration findings.

18. If critical findings → route to appropriate builder. Re-run that builder → re-run fan-out (step 13) → re-run test-verifier → re-run validator.

19. Show all findings to user. Ask: "Ready to open the PR?"

20. **On user approval or rejection exit**: `rm -rf "$artifact_root"`. Do NOT cleanup before user approves or exits.

## Routing Rules by Mode

**hotfix**: Steps 2, 3, 10, 12, 13, 16, 17, 19, 20. No story/spec gates. architecture-reviewer still runs. migration-reviewer conditional.

**backend-only**: Steps 2–8, 10, 12, 13, 16, 17, 19, 20. Skip frontend-builder (step 14). Fan-out still runs security + architecture + migration + docs.

**frontend-only**: Steps 2–8, 14, 16, 17, 19, 20. Skip backend-builder (step 10). No architecture-reviewer (no backend changes). migration-reviewer skipped. API contract must already exist and be valid.

**docs-only**: Steps 2, 3, 4, 19, 20. No implementation. Validator reviews researcher findings and story only.

## Chain Integrity Rules

- Never skip human approval points (story, brief).
- Validate `context_sha` before any builder edits files.
- Generate `architecture-contract.yaml` at step 2 — all reviewers and builders depend on it.
- Run yamllint before fan-out.
- Run depcruise before fan-out if available; architecture-reviewer handles grep-based fallback.
- architecture-reviewer always runs on backend-only and full-feature modes.
- migration-reviewer only runs when migration files are in scope — always update manifest.
- docs-writer is non-blocking — never halt the chain on incomplete docs.
- Fan-out agents run in parallel — do not serialize them.
- If backend re-runs: full fan-out restart, not partial.
- Keep artifacts until user approves or exits.
- Update `manifest.yaml` after every phase.
- On crash: read manifest, restart from incomplete phase.
