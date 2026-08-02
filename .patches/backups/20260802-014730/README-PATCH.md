# workspace-default readiness ownership fix

Fixes `WORKSPACE_BOOTSTRAP_FAILED: exit status 7`.

`curl` exit 7 means the health check connected before the service was listening.

Changes:
- `startup.sh` launches PostgreSQL, backend, and frontend only.
- `startup.sh` no longer calls `ready.sh`.
- frontend is explicitly started on 8080.
- backend is explicitly started on 4000.
- `ready.sh` remains a single authoritative probe with useful diagnostics.
- TenderHeart performs the retries.

Apply and push this patch before retrying a new or existing sandbox.
