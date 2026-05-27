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

At chain start:

```
context_sha=$(git rev-parse HEAD)
artifact_root=$(mktemp -d "/tmp/factory/${context_sha}-XXXXXX")
```

`mktemp -d` guarantees a unique, non-colliding directory even if two runs start within the same second.

All artifacts for this run live under `$artifact_root/`.

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
  frontend-summary: pending
  acceptance-test-report: pending

phase: initialized
```

After each phase completes, update `manifest.yaml`:
- Set the corresponding `artifacts` entry to `present`
- Update `phase` to the current phase name

If the chain crashes, the manifest shows exactly where execution stopped. Resume by reading the manifest and restarting from the incomplete phase.

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
| `$artifact_root/manifest.yaml` | orchestrator | orchestrator, resume logic |

Each builder writes its artifact BEFORE the next builder starts. Frontend-builder reads `api-contract.yaml` directly, not prose.

## Context SHA Pinning

`context_sha` is captured at chain start. Every agent validates `git rev-parse HEAD` matches before executing. If SHA changed mid-chain: abort, surface conflict, let user decide to continue or restart.

## Contract Validation Gate

After backend-builder writes `api-contract.yaml` and before frontend-builder starts:

1. Run yamllint on `$artifact_root/api-contract.yaml` if available; skip if not installed.
2. If yamllint fails: abort chain, surface error, do not start frontend-builder.
3. frontend-builder reads `api-contract.yaml` and validates `schema_version` and `context_sha` fields match the chain's values. If mismatch: abort.

## Contract Change Reconciliation

If backend-builder is re-run after validator feedback, the `api-contract.yaml` is regenerated with a new `generated_at` timestamp.

- Invalidate any in-progress frontend work.
- Re-run frontend-builder from scratch against the updated contract.
- Do not allow frontend-builder to continue with a stale contract.
- Update `manifest.yaml` `phase` and `artifacts` entries accordingly.

## Process (full-feature mode)

1. Capture `context_sha`. Create `artifact_root` via `mktemp -d`. Write `manifest.yaml`.

2. Invoke **codebase-researcher**. Write findings to `$artifact_root/researcher-findings.md`. Update `manifest.yaml`: `researcher-findings: present`, `phase: researcher`.

3. Invoke **story-writer**. Read findings. Write story to `$artifact_root/user-story.md`. Update manifest.

4. Show the story to the user. Ask: "Does this match what you want? Reply 'approved' to continue, describe what to change, or 'reject' to stop."
   - Approved → continue.
   - Changes requested → re-invoke story-writer. Repeat until approved or rejected.
   - Rejected → stop. Summarise what was explored. Do NOT cleanup — user may want to inspect artifacts before exiting.

5. Validate `context_sha`. If drift → abort.

6. Invoke **spec-writer**. Read story + findings. Write brief to `$artifact_root/technical-brief.md`. Update manifest.

7. Show the brief to the user. Ask: "Any design red flags? Reply 'approved' to continue, describe what to change, or 'reject' to stop."
   - Approved → continue.
   - Changes requested → re-invoke spec-writer. Repeat until approved or rejected.
   - Rejected → stop. Keep approved story. Do NOT cleanup.

8. Validate `context_sha`. If drift → abort.

9. Invoke **backend-builder**. Read brief + findings from `$artifact_root/`. Validate SHA. Write implementation. Write `$artifact_root/api-contract.yaml` (with `schema_version`, `context_sha`, `generated_at`) and `$artifact_root/backend-summary.md`. Update manifest. Wait. Validate SHA before any edit.

10. **Contract gate**: Run yamllint on `$artifact_root/api-contract.yaml` if available. Fail on error. frontend-builder then reads it, validates `schema_version` and `context_sha`.

11. Invoke **frontend-builder**. Read `$artifact_root/api-contract.yaml` (mandatory), brief, findings. Validate contract metadata. Write implementation. Write `$artifact_root/frontend-summary.md`. Update manifest. Wait.

12. Validate `context_sha`. If drift → abort and surface conflict.

13. Invoke **test-verifier**. Read story, brief, `api-contract.yaml`, both summaries. Write acceptance tests. Write `$artifact_root/acceptance-test-report.md`. Update manifest.

14. Invoke **implementation-validator**. Read all artifacts. Report findings grouped by severity.

15. If critical findings → route to appropriate builder. If backend-builder re-runs: regenerate `api-contract.yaml`, then re-run frontend-builder from scratch (step 11), then re-run test-verifier (step 13), then re-run validator (step 14). Update manifest at each step.

16. Show findings to user. Ask: "Ready to open the PR?"

17. **On user approval or rejection exit**: Cleanup. `rm -rf "$artifact_root"`. Do NOT cleanup before user has approved or exited — user may want to inspect artifacts.

18. (If user requests specific artifact inspection before approving: serve it from `$artifact_root` before cleanup runs.)

## Routing Rules by Mode

**hotfix**: Steps 2, 9, 13, 14, 16, 17. Backend-builder reads researcher findings directly. No story/spec gates.

**backend-only**: Steps 2–8, 9, 13, 14, 16, 17. Skip step 10 (no frontend).

**frontend-only**: Steps 2–8, 11, 13, 14, 16, 17. Skip step 9. API contract must already exist from prior backend run. Validate contract exists and is valid before starting.

**docs-only**: Steps 2, 3, 4, 14, 16, 17. No implementation. Validator reviews findings and story only.

## Chain Integrity Rules

- Never skip the human approval points (story, brief).
- Validate `context_sha` before any builder edits files.
- Run yamllint on `api-contract.yaml` before frontend-builder starts.
- frontend-builder validates `schema_version` and `context_sha` in the contract before consuming.
- If backend-builder re-runs, frontend-builder must restart from scratch.
- Keep artifacts on disk until user approves or exits — never cleanup before approval.
- If SHA drifts mid-chain: abort, surface conflict.
- If any agent reports it cannot complete its task: stop and surface the reason.
- Update `manifest.yaml` after each phase completes.
- On crash resume: read manifest to find last completed phase and restart from there.
