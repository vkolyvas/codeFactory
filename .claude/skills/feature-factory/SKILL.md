---
name: feature-factory
description: Use this skill when the user asks to build, ship, or implement a feature end to end. Runs the full chain of seven subagents with human approval points after the story and the brief, runs the build agents in order (backend, frontend, test-verifier), then validates. Triggers on: "build a feature", "ship a feature", "run the factory", "feature factory", "/feature-factory".
---

## Mode Selection

Before running the chain, determine the execution mode from the user's request:

- **full-feature** (default): researcher → story → spec → backend → frontend → test → validate
- **hotfix**: researcher → backend → test → validate (skips story and spec)
- **backend-only**: researcher → story → spec → backend → test → validate (skips frontend)
- **frontend-only**: researcher → story → spec → frontend → test → validate (skips backend)
- **docs-only**: researcher → story → docs → validate

Ask the user to confirm the mode if ambiguous.

## Run-Scoped Artifact Root

At chain start, capture:

```
context_sha=$(git rev-parse HEAD)
timestamp=$(date +%Y%m%dT%H%M%S)
artifact_root="/tmp/factory/${context_sha}-${timestamp}"
mkdir -p "$artifact_root"
```

All artifacts for this run live under `$artifact_root/`. No other run can use this path.

## Artifact File Map

| Artifact | Written by | Read by |
|---|---|---|
| `$artifact_root/researcher-findings.md` | codebase-researcher | story-writer, spec-writer, backend-builder, frontend-builder |
| `$artifact_root/user-story.md` | story-writer | spec-writer, test-verifier, implementation-validator |
| `$artifact_root/technical-brief.md` | spec-writer | backend-builder, frontend-builder, test-verifier |
| `$artifact_root/api-contract.yaml` | backend-builder | frontend-builder, test-verifier |
| `$artifact_root/backend-summary.md` | backend-builder | frontend-builder, test-verifier |
| `$artifact_root/frontend-summary.md` | frontend-builder | test-verifier, implementation-validator |
| `$artifact_root/acceptance-test-report.md` | test-verifier | implementation-validator |

Each builder writes its artifact BEFORE the next builder starts. Frontend-builder reads `api-contract.yaml` directly, not prose.

## Context SHA Pinning

`context_sha` is captured at chain start. Every agent validates `git rev-parse HEAD` matches before executing. If SHA changed mid-chain: abort, surface conflict, let user decide to continue or restart.

## Contract Validation Gate

After backend-builder writes `api-contract.yaml` and before frontend-builder starts:

1. Run yamllint on `$artifact_root/api-contract.yaml` if available; skip if not installed.
2. If yamllint fails: abort chain, surface error, do not start frontend-builder.
3. frontend-builder reads `api-contract.yaml` and validates `schema_version` and `context_sha` fields match the chain's values. If mismatch: abort.

## Contract Change Reconciliation

If backend-builder is re-run after validator feedback (step 14 loop), the `api-contract.yaml` is regenerated with a new `generated_at` timestamp.

- Invalidate any in-progress frontend work.
- Re-run frontend-builder from scratch against the updated contract.
- Do not allow frontend-builder to continue with a stale contract.

## Process (full-feature mode)

1. Capture `context_sha` and `timestamp`. Set `artifact_root`. Create directory.

2. Invoke **codebase-researcher**. Write findings to `$artifact_root/researcher-findings.md`.

3. Invoke **story-writer**. Read findings. Write story to `$artifact_root/user-story.md`.

4. Show the story to the user. Ask: "Does this match what you want? Reply 'approved' to continue, describe what to change, or 'reject' to stop."
   - Approved → continue.
   - Changes requested → re-invoke story-writer. Repeat until approved or rejected.
   - Rejected → stop. Summarise what was explored.

5. Validate `context_sha`. If drift → abort.

6. Invoke **spec-writer**. Read story + findings. Write brief to `$artifact_root/technical-brief.md`.

7. Show the brief to the user. Ask: "Any design red flags? Reply 'approved' to continue, describe what to change, or 'reject' to stop."
   - Approved → continue.
   - Changes requested → re-invoke spec-writer. Repeat until approved or rejected.
   - Rejected → stop. Keep approved story.

8. Validate `context_sha`. If drift → abort.

9. Invoke **backend-builder**. Read brief + findings from `$artifact_root/`. Validate SHA. Write implementation. Write `$artifact_root/api-contract.yaml` (with `schema_version`, `context_sha`, `generated_at`) and `$artifact_root/backend-summary.md`. Wait. Validate SHA before any edit.

10. **Contract gate**: Run yamllint on `$artifact_root/api-contract.yaml` if available. Fail on error. frontend-builder then reads it, validates `schema_version` and `context_sha`.

11. Invoke **frontend-builder**. Read `$artifact_root/api-contract.yaml` (mandatory, not optional), brief, findings. Write implementation. Write `$artifact_root/frontend-summary.md`. Wait.

12. Validate `context_sha`. If drift → abort and surface conflict.

13. Invoke **test-verifier**. Read story, brief, `api-contract.yaml`, both summaries. Write acceptance tests. Write `$artifact_root/acceptance-test-report.md`.

14. Invoke **implementation-validator**. Read all artifacts. Report findings grouped by severity.

15. If critical findings → route to appropriate builder. If backend-builder re-runs: regenerate `api-contract.yaml`, then re-run frontend-builder from scratch (step 11), then re-run test-verifier (step 13), then re-run validator (step 14).

16. **Cleanup**: After final user approval, remove `$artifact_root` directory. `rm -rf "$artifact_root"`.

17. Show findings to user. Ask: "Ready to open the PR?"

## Routing Rules by Mode

**hotfix**: Steps 2, 9 (skip spec/story gates), 13, 14, 16, 17. Backend-builder reads researcher findings directly.

**backend-only**: Steps 2–8, 9, 13, 14, 16, 17. Skip step 10 (no frontend).

**frontend-only**: Steps 2–8, 11, 13, 14, 16, 17. Skip step 9. API contract must already exist from prior backend run. Validate this before starting.

**docs-only**: Steps 2, 3, 4, 14, 16, 17. No implementation. Validator reviews findings and story only.

## Chain Integrity Rules

- Never skip the human approval points (story, brief).
- Validate `context_sha` before any builder edits files.
- Run yamllint on `api-contract.yaml` before frontend-builder starts.
- frontend-builder validates `schema_version` and `context_sha` in the contract before consuming.
- If backend-builder re-runs, frontend-builder must restart from scratch.
- Remove `$artifact_root` at chain end.
- If SHA drifts mid-chain: abort, surface conflict.
- If any agent reports it cannot complete its task: stop and surface the reason.
