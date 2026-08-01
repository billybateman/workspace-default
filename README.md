# workspace-default

Canonical full-stack workspace repository for Project TenderHeart.

## Runtime

- React + Vite frontend on port 5173
- Node + Express backend on port 4001
- PostgreSQL on port 5432
- Idempotent startup, migration, seed, and readiness scripts

## Commands

```bash
npm install
npm --prefix frontend install
npm --prefix backend install
bash startup.sh
```
