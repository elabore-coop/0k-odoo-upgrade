#!/bin/bash

DB_CONTAINER_NAME="lokavaluto_postgres_1"

# Function to launch an SQL request to the postgres container
query_postgres_container(){
    local query="$1"
    if [ -z "$query" ]; then
	return 0
    fi
    local result

    if ! result=$(docker exec -u 70 "$DB_CONTAINER_NAME" psql -d ou15 -t -A -c "$query" 2>&1); then
        printf "Failed to execute SQL query: %s\n" "$query" >&2
        printf "Error: %s\n" "$result" >&2
        exit 1
    fi
    # Remove leading/trailing whitespace from result
    result=$(echo "$result" | xargs)
}

echo "Prepare migration to 15.0..."

# Copy database
docker exec -u 70 "$DB_CONTAINER_NAME" pgm cp -f ou14 ou15@ou15

# Execute SQL pre-migration commands
PRE_MIGRATE_SQL=$(cat <<'EOF'
/* Delete add-on 'account_usability' as its name has changed and another 'account_usability' add-on is created  */
DELETE FROM ir_module_module WHERE name = 'account_usability';
DELETE FROM ir_model_data WHERE module = 'base' AND name = 'module_account_usability';
EOF
)
echo "SQL command = $PRE_MIGRATE_SQL"
query_postgres_container "$PRE_MIGRATE_SQL" >&1


# Copy filestores
rm -rf /srv/datastore/data/ou15/var/lib/odoo/filestore/ou15 || exit 1
cp -a /srv/datastore/data/ou14/var/lib/odoo/filestore/ou14 /srv/datastore/data/ou15/var/lib/odoo/filestore/ou15 || exit 1

echo "Ready for migration to 15.0!"
