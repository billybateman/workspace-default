# workspace-default refresh-safe bootstrap fix

Fixes the stale/corrupted sandbox bootstrap seen in the logs.

Changes:
- Corrects `timestamptz NOTNULL` to `timestamptz NOT NULL`.
- Uses backend port 4000 consistently.
- Makes the Vite proxy derive its target from BACKEND_PORT.
- Keeps the frontend on 5173.

Apply and push this patch before applying the TenderHeart reconnect patch.
