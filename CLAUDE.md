# Project Instructions

Generic software factory project. Adapt this CLAUDE.md to your stack.

## Stack

Replace with your actual stack:
- Framework: (e.g., Next.js 14, Node.js, Django)
- Database: (e.g., PostgreSQL + Prisma)
- Auth: (e.g., Auth.js, Clerk, custom JWT)
- Jobs: (e.g., BullMQ, Celery, node-cron)
- Email: (e.g., Resend, SendGrid, AWS SES)
- Testing: (e.g., Vitest, Jest, Playwright)

## Commands

Replace with your actual commands:
- `npm run dev` — start dev server
- `npm test` — run unit tests
- `npm run typecheck` — type-check the project
- `npm run lint` — lint the project
- `npx prisma migrate dev` — run migrations locally

## Architecture

- Business logic lives in services or domain modules
- API routes stay thin and call into services
- Reuse existing infrastructure before adding new dependencies
- Tenant isolation enforced at service layer, not route layer
- Background jobs reuse existing scheduler/queue system

## Documentation

For deeper context, consult:
- `docs/architecture.md` — service boundaries, request flow, tenant isolation
- `docs/billing.md` — payment handling, invoice lifecycle, proration
- `docs/email.md` — template system, available templates
- `docs/jobs.md` — queue names, job patterns, retry/backoff policy
- `docs/db.md` — schema conventions, tenant isolation, soft-delete rules
- `prisma/schema.prisma` — source of truth for data model
- ADRs in `docs/adr/` — past architecture decisions

For library specifics, check official docs rather than guessing.

## Testing

- Every feature has success, validation failure, and not-found tests
- Use test data builders, not inline setup objects
- Do not mock the database unless existing tests already do
- Acceptance tests verify user story behaviour end-to-end

## Don't Do

- Do not log raw payment payloads or secrets
- Do not return database errors directly to the client
- Do not edit merged migrations
- Do not add new dependencies without explicit discussion
- Do not change files outside the agreed feature scope
