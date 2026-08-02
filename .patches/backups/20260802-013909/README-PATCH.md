# workspace-default focused sandbox workflow patch

Built against workspace-default main commit:
381e71a89617a084462d756d40a516fa3a5b7e7e

Changes:
- setup.sh no longer clones or refreshes the repository.
- TenderHeart must clone first.
- setup.sh owns PostgreSQL installation/configuration, .env, dependencies, migrations, seeders, and initial startup.
- startup.sh only restarts PostgreSQL and application services.
- ready.sh is the authoritative PostgreSQL/backend/frontend readiness probe.
