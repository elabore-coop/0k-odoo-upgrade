#!/bin/bash

DB_CONTAINER_NAME="lokavaluto_postgres_1"

# Function to launch an SQL request to the postgres container
query_postgres_container(){
    local query="$1"
    if [ -z "$query" ]; then
	return 0
    fi
    local result
    if ! result=$(docker exec -u 70 "$DB_CONTAINER_NAME" psql -d ou16 -t -A -c "$query" 2>&1); then
        printf "Failed to execute SQL query: %s\n" "$query" >&2
        printf "Error: %s\n" "$result" >&2
        exit 1
    fi
    # Remove leading/trailing whitespace from result
    result=$(echo "$result" | xargs)
    echo "$result"
}

echo "Prepare migration to 16.0..."

# Copy database
docker exec -u 70 "$DB_CONTAINER_NAME" pgm cp -f ou15 ou16@ou16

# Execute SQL pre-migration commands
PRE_MIGRATE_SQL=$(cat <<'EOF'
/* Remove duplicate entries in model utm.source */
DELETE FROM utm_source
WHERE id IN (
    SELECT id
    FROM (
        SELECT id,
               ROW_NUMBER() OVER (PARTITION BY name ORDER BY id) as row_num
        FROM utm_source
    ) t
    WHERE t.row_num > 1
);
EOF
	       )
echo "SQL command = $PRE_MIGRATE_SQL"
query_postgres_container "$PRE_MIGRATE_SQL"


# Copy filestores
rm -rf /srv/datastore/data/ou16/var/lib/odoo/filestore/ou16 || exit 1
cp -a /srv/datastore/data/ou15/var/lib/odoo/filestore/ou15 /srv/datastore/data/ou16/var/lib/odoo/filestore/ou16 || exit 1

echo "Ready for migration to 16.0!"
