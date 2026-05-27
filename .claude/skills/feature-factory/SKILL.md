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

## Context SHA Pinning

At chain start, capture the repository state:

```
git rev-parse HEAD
```

Record the SHA. Every agent in the chain must validate that `git rev-parse HEAD` still matches before executing. If the SHA changed mid-chain, abort and surface the conflict to the user.

## Artifact Files

Instead of prose summaries, agents write and read machine-readable artifacts:

| Artifact | Written by | Read by |
|---|---|---|
| `/tmp/factory/researcher-findings.md` | codebase-researcher | story-writer, spec-writer, backend-builder, frontend-builder |
| `/tmp/factory/user-story.md` | story-writer | spec-writer, test-verifier, implementation-validator |
| `/tmp/factory/technical-brief.md` | spec-writer | backend-builder, frontend-builder, test-verifier |
| `/tmp/factory/api-contract.yaml` | backend-builder | frontend-builder, test-verifier |
| `/tmp/factory/backend-summary.md` | backend-builder | frontend-builder, test-verifier |
| `/tmp/factory/frontend-summary.md` | frontend-builder | test-verifier, implementation-validator |
| `/tmp/factory/acceptance-test-report.md` | test-verifier | implementation-validator |

Each builder writes its artifact BEFORE the next builder starts. Frontend-builder reads `api-contract.yaml` directly, not prose.

## Process (full-feature mode)

1. **git rev-parse HEAD** → record as `context_sha`

2. Invoke **codebase-researcher**. Write findings to `/tmp/factory/researcher-findings.md`.

3. Invoke **story-writer**. Read findings. Write user story to `/tmp/factory/user-story.md`.

4. Show the story to the user. Ask: "Does this match what you want? Reply 'approved' to continue, describe what to change, or 'reject' to stop."
   - Approved → continue.
   - Changes requested → re-invoke story-writer with feedback. Repeat until approved or rejected.
   - Rejected → stop. Summarise what was explored.

5. Validate `context_sha` still matches. If not, abort.

6. Invoke **spec-writer**. Read story + findings. Write brief to `/tmp/factory/technical-brief.md`.

7. Show the brief to the user. Ask: "Any design red flags? Reply 'approved' to continue, describe what to change, or 'reject' to stop."
   - Approved → continue.
   - Changes requested → re-invoke spec-writer with feedback. Repeat until approved or rejected.
   - Rejected → stop. Keep the approved story.

8. Validate `context_sha` still matches. If not, abort.

9. Invoke **backend-builder**. Read brief + findings. Write implementation. Write `api-contract.yaml` and `backend-summary.md`. Wait for completion. Validate `context_sha` before editing.

10. Invoke **frontend-builder**. Read `api-contract.yaml` (NOT prose summary), brief, findings. Write implementation. Write `frontend-summary.md`. Wait for completion.

11. Validate `context_sha` still matches. If not, abort and surface conflict.

12. Invoke **test-verifier**. Read story, brief, `api-contract.yaml`, both summaries. Write acceptance tests. Write `acceptance-test-report.md`.

13. Invoke **implementation-validator**. Read all artifacts. Report findings grouped by severity.

14. If critical findings → route to appropriate builder → re-run test-verifier → re-run validator.

15. Show findings to user. Ask: "Ready to open the PR?"

## Routing Rules by Mode

**hotfix** (no story, no spec):
- Steps 2, 9, 12, 13, 15
- Backend-builder reads researcher findings directly
- No brief approval gate

**backend-only** (no frontend):
- Steps 2, 3, 4, 5, 6, 7, 8, 9, 12, 13, 15
- Skip step 10

**frontend-only** (no backend):
- Steps 2, 3, 4, 5, 6, 7, 8, 10, 12, 13, 15
- Skip step 9
- frontend-builder reads researcher findings for context only
- API contract must already exist from prior backend run (confirm before starting)

**docs-only**:
- Steps 2, 3, 4, 13, 15
- Skip implementation entirely
- Validator reviews researcher findings and story only

## Chain Integrity Rules

- Never skip the human approval points (story, brief).
- Validate `context_sha` before any builder edits files.
- Each builder writes its artifact before the next builder starts.
- Frontend-builder MUST read `api-contract.yaml`, not prose summaries.
- Test-verifier MUST read `api-contract.yaml`, not assumptions.
- If SHA drifts mid-chain: abort, surface conflict, let user decide whether to continue or restart.
- If any agent reports it cannot complete its task: stop and surface the reason.
