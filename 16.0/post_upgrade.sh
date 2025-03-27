#!/bin/bash

echo "POST migration to 16.0..."

# Digital currency specific - to comment if not needed
INVOICE_NAME_SQL=$(cat <<'EOF'
UPDATE credit_request
SET invoice_id = (
    SELECT id
    FROM account_move
    WHERE account_move.name = credit_request.invoice_name
);
EOF
)
query_postgres_container "$INVOICE_NAME_SQL" ou16 || exit 1

echo "END POST migration to 16.0."
