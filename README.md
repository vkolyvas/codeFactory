# Codefactory

AI-powered multi-agent feature factory. Define a feature in natural language — researchers, specs it, builds it, reviews it, and tests it — then drops a PR on your desk.

---

## Logo

![Codefactory](/.claude/assets/logo.svg)

---

## Features

### 4-Lane Pipeline
Agents split into Builders (write), Reviewers (check), Verifiers (test), and Docs (write). Each lane has explicit ownership boundaries enforced by ESLint and depcruise.

### Parallel Fan-Out Review
Security, architecture, migration, and docs reviewers run simultaneously after the build — no sequential bottle-necks.

### Declared Architecture
`architecture-contract.yaml` defines what should exist, not what does. architecture-reviewer generates `observed-dependencies.json` from depcruise and diffs the two. Chaos encoded from legacy repos does not become enforced truth.

### Escape Hatches
Cross-boundary calls allowed with `// override: <documented_reason>` annotation. architecture-reviewer allows it if the pattern is allowlisted in `escape_hatches`.

### Pattern-Reuse Before Invention
Builders find 3 nearest reference implementations ranked by dependency-graph proximity (depcruise distance), not lexical similarity. The structurally closest match wins.

### SHA-Pinned Context
`git rev-parse HEAD` captured at chain start. Every agent validates it before editing. Context drift kills the run before bad code ships.

### Machine-Readable Contracts
`api-contract.yaml` is the single source of truth for endpoint shapes — not prose summaries. frontend-builder validates it before consuming.

---

## Quick Start

```bash
# 1. Clone the factory template
git clone https://github.com/vkolyvas/codeFactory.git
cd codeFactory

# 2. Wire it into your project
cp -r .claude CLAUDE.md /path/to/your/project/
cd /path/to/your/project

# 3. Customize CLAUDE.md for your stack
# Replace the stack placeholders with your actual:
# - Framework (Next.js 14, Django, etc.)
# - Database (Postgres + Prisma, etc.)
# - Commands (npm run dev, npm test, etc.)
```

---

## Usage

In any Claude Code conversation within a project wired with the factory:

```
/feature-factory
```

The chain walks through:

| Phase | What happens |
|---|---|
| **researcher** | Maps codebase, patterns, risks |
| **story-writer** | Produces user story with acceptance criteria |
| **spec-writer** | Produces technical brief with data model, API, tests |
| **backend-builder** | Implements backend (services, routes, migrations, tests) |
| **fan-out** | security + architecture + migration + docs reviewers in parallel |
| **frontend-builder** | Implements frontend, reads and validates api-contract.yaml |
| **test-verifier** | Writes acceptance tests against the user story |
| **implementation-validator** | Groups findings by severity |

You approve at two points: after the story and after the brief. PR opens when all findings are resolved.

---

## Routing Modes

```
full-feature    → researcher → story → spec → backend → fan-out → frontend → test → validate
hotfix         → researcher → backend → fan-out → test → validate  (no story/spec gates)
backend-only   → researcher → story → spec → backend → fan-out → test → validate  (no frontend)
frontend-only → researcher → story → spec → frontend → test → validate  (api-contract must pre-exist)
docs-only      → researcher → story → docs → validate  (no implementation)
```

---

## Project Structure

```
.claude/
├── agents/
│   ├── codebase-researcher.md      # Maps codebase structure
│   ├── story-writer.md            # User story + acceptance criteria
│   ├── spec-writer.md             # Technical brief
│   ├── backend-builder.md         # Services, routes, migrations, tests
│   ├── frontend-builder.md        # Components, pages, hooks, tests
│   ├── test-verifier.md           # Acceptance tests
│   ├── implementation-validator.md # Severity-grouped findings
│   ├── security-reviewer.md       # Auth, RBAC, secrets, rate limits
│   ├── architecture-reviewer.md   # Forbidden imports, layer crossings
│   ├── migration-reviewer.md     # Destructive migrations, nullable cascades
│   ├── docs-writer.md             # CHANGELOG, docs surface (non-blocking)
│   └── pr-reviewer.md             # PR checklist review
├── skills/
│   ├── feature-factory/
│   │   └── SKILL.md               # Orchestrator skill (20-step chain)
│   └── build-with-tests/
│       └── SKILL.md               # read → find refs → write tests → run
└── hooks/
    └── pre-commit.sh              # Blocks credential files on commit
```

---

## CI Enforcement

```bash
# Dependency boundary checks
npx depcruise src --config .dependency-cruiser.yaml --validate

# ESLint layer boundaries
eslint --config .clairec-lint-boundaries.json src/
```

---

## Wiring to an Existing Repo

```bash
# Copy the factory into any existing project
cp -r /path/to/codeFactory/.claude /path/to/your/project/
cp /path/to/codeFactory/CLAUDE.md /path/to/your/project/

# Then customize CLAUDE.md:
# - Fill in your stack (framework, DB, auth, jobs, email)
# - Set your actual commands (dev, test, typecheck, lint)
# - Update the architecture rules and don't-do list
# - Add service-specific docs (docs/architecture.md, docs/billing.md, etc.)

# Done. Now trigger the factory:
/feature-factory
```
