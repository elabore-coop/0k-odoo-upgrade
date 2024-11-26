#!/bin/bash

DB_NAME="$1"
ODOO_SERVICE="$2"

FINALE_SQL=$(cat <<'EOF'
/*Delete sequences that prevent Odoo to start*/
drop sequence base_registry_signaling;
drop sequence base_cache_signaling;
EOF
)
query_postgres_container "$FINALE_SQL" "$DB_NAME" || exit 1


# Give back the right to user to access to the tables
# docker exec -u 70 "$DB_CONTAINER_NAME" pgm chown "$FINALE_SERVICE_NAME" "$DB_NAME"


# Launch Odoo with database in finale version to run all updates
compose --debug run "$ODOO_SERVICE" -u all --stop-after-init --no-http
