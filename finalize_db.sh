#!/bin/bash

DB_NAME="$1"
ODOO_SERVICE="$2"
DB_CONTAINER_NAME="lokavaluto_postgres_1"

# Function to launch an SQL request to the postgres container
query_postgres_container(){
    local query="$1"
    if [ "$query" ]; then
	return 0
    fi
    local result
    if ! result=$(docker exec -u 70 "$DB_CONTAINER_NAME" psql -d "$DB_NAME" -t -A -c "$query" 2>&1); then
        printf "Failed to execute SQL query: %s\n" "$query" >&2
        printf "Error: %s\n" "$result" >&2
        exit 1
    fi
    # Remove leading/trailing whitespace from result
    result=$(echo "$result" | xargs)
    echo "$result"
}

FINALE_SQL=$(cat <<'EOF'
/*Delte sequences that prevent Odoo to start*/
drop sequence base_registry_signaling;
drop sequence base_cache_signaling;
EOF
)
query_postgres_container "$FINALE_SQL"


# Give back the right to user to access to the tables
# docker exec -u 70 "$DB_CONTAINER_NAME" pgm chown "$FINALE_SERVICE_NAME" "$DB_NAME"


# Launch Odoo with database in finale version to run all updates
compose --debug run "$ODOO_SERVICE" -u all --stop-after-init --no-http
