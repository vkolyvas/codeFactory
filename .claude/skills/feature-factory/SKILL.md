---
name: feature-factory
description: Use this skill when the user asks to build, ship, or implement a feature end to end. Runs the full chain with parallel reviewer fan-out after builds, then validation. Triggers on: "build a feature", "ship a feature", "run the factory", "feature factory", "/feature-factory".
---

## Mode Selection

Before running the chain, determine the execution mode:

- **full-feature** (default): researcher → story → spec → backend → [security | migration? | docs] → frontend → test → validate
- **hotfix**: researcher → backend → [security | migration?] → test → validate (skips story and spec)
- **backend-only**: researcher → story → spec → backend → [security | migration?] → test → validate (skips frontend)
- **frontend-only**: researcher → story → spec → frontend → test → validate (API contract must pre-exist)
- **docs-only**: researcher → story → docs → validate

Ask the user to confirm the mode if ambiguous.

## Lane Model

Agents belong to one of four lanes:

| Lane | Agents | May Edit | Blocking |
|------|--------|----------|----------|
| A — Builders | backend-builder, frontend-builder | Yes (source) | Yes |
| B — Reviewers | security-reviewer, migration-reviewer | No | Yes |
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
  backend-summary: pending
  security-findings: pending
  migration-findings: not_applicable
  docs-report: not_applicable
  frontend-summary: pending
  acceptance-test-report: pending

phase: initialized
```

After each phase: update `manifest.yaml` artifacts entry and `phase` field.

On crash: read manifest → find incomplete phase → resume from there.

## Artifact File Map

| Artifact | Written by | Read by |
|---|---|---|
| `$artifact_root/researcher-findings.md` | codebase-researcher | story-writer, spec-writer, builders |
| `$artifact_root/user-story.md` | story-writer | spec-writer, test-verifier, validator |
| `$artifact_root/technical-brief.md` | spec-writer | builders, reviewers, verifier |
| `$artifact_root/api-contract.yaml` | backend-builder | frontend-builder, test-verifier |
| `$artifact_root/backend-summary.md` | backend-builder | reviewers, frontend-builder |
| `$artifact_root/security-findings.md` | security-reviewer | validator |
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

## Contract Change Reconciliation

If backend-builder re-runs after validator feedback:
1. Regenerate `api-contract.yaml` with new `generated_at`.
2. Invalidate all downstream work (frontend, reviewers).
3. Re-run the full fan-out from step 11.

## Process (full-feature mode)

1. Capture `context_sha`. Create `artifact_root`. Write `manifest.yaml`.

2. Invoke **codebase-researcher**. Write `$artifact_root/researcher-findings.md`. Update manifest.

3. Invoke **story-writer**. Read findings. Write `$artifact_root/user-story.md`. Update manifest.

4. Show story to user. Ask: approved / changes / reject.
   - Approved → continue.
   - Changes → re-invoke story-writer. Repeat.
   - Rejected → stop. Do NOT cleanup. User may inspect artifacts.

5. Validate `context_sha`. If drift → abort.

6. Invoke **spec-writer**. Write `$artifact_root/technical-brief.md`. Update manifest.

7. Show brief to user. Ask: approved / changes / reject.
   - Approved → continue.
   - Changes → re-invoke spec-writer. Repeat.
   - Rejected → stop. Keep approved story. Do NOT cleanup.

8. Validate `context_sha`. If drift → abort.

9. Invoke **backend-builder**. Validate SHA. Write implementation. Write `$artifact_root/api-contract.yaml` and `$artifact_root/backend-summary.md`. Update manifest. Wait.

10. **Contract gate**: yamllint on `api-contract.yaml`. Fail on error.

11. **Fan-out (parallel)** — all three run simultaneously:
    - Invoke **security-reviewer**. Read brief + implementation. Write `$artifact_root/security-findings.md`. Update manifest: `security-findings: present`.
    - Invoke **migration-reviewer** — ONLY if brief or changed files include `prisma/`, `migrations/`, or `schema.prisma`. If not applicable: write `migration-findings: not_applicable` to manifest and skip. If applicable: write findings to `$artifact_root/migration-findings.md`. Update manifest.
    - Invoke **docs-writer** — non-blocking. Read summaries. Write `$artifact_root/docs-report.md`. If nothing to document: write `docs-report: nothing_to_document` to manifest. Update manifest. **Do not block chain on docs.**
    Wait for all three to complete.

12. Invoke **frontend-builder**. Read `api-contract.yaml` (mandatory, not optional). Validate `schema_version` + `context_sha`. Write `$artifact_root/frontend-summary.md`. Update manifest. Wait.

13. Validate `context_sha`. If drift → abort and surface conflict.

14. Invoke **test-verifier**. Read story, brief, `api-contract.yaml`, both summaries. Write `$artifact_root/acceptance-test-report.md`. Update manifest.

15. Invoke **implementation-validator**. Read all artifacts. Report findings grouped by severity, including security and migration findings.

16. If critical findings → route to appropriate builder. Re-run that builder → re-run fan-out (step 11) → re-run test-verifier → re-run validator.

17. Show all findings to user. Ask: "Ready to open the PR?"

18. **On user approval or rejection exit**: `rm -rf "$artifact_root"`. Do NOT cleanup before user approves or exits.

## Routing Rules by Mode

**hotfix**: Steps 2, 9, 11 (fan-out), 14, 15, 17, 18. No story/spec gates. migration-reviewer conditional.

**backend-only**: Steps 2–8, 9, 11, 14, 15, 17, 18. Skip frontend-builder (step 12). Fan-out still runs security + migration + docs.

**frontend-only**: Steps 2–8, 12, 14, 15, 17, 18. Skip backend-builder (step 9). API contract must already exist and be valid. migration-reviewer skipped (no backend changes).

**docs-only**: Steps 2, 3, 4, 17, 18. No implementation. Validator reviews researcher findings and story only.

## Chain Integrity Rules

- Never skip human approval points (story, brief).
- Validate `context_sha` before any builder edits files.
- Run yamllint before fan-out.
- migration-reviewer only runs when migration files are in scope — always update manifest.
- docs-writer is non-blocking — never halt the chain on incomplete docs.
- Fan-out agents run in parallel — do not serialize them.
- If backend re-runs: full fan-out restart, not partial.
- Keep artifacts until user approves or exits.
- Update `manifest.yaml` after every phase.
- On crash: read manifest, restart from incomplete phase.
