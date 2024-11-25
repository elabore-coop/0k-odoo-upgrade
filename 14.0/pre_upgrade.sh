#!/bin/bash

DB_CONTAINER_NAME="lokavaluto_postgres_1"

# Function to launch an SQL request to the postgres container
query_postgres_container(){
    local query="$1"
    if [ -z "$query" ]; then
	return 0
    fi
    local result
    if ! result=$(docker exec -u 70 "$DB_CONTAINER_NAME" psql -d ou14 -t -A -c "$query" 2>&1); then
        printf "Failed to execute SQL query: %s\n" "$query" >&2
        printf "Error: %s\n" "$result" >&2
        exit 1
    fi
    # Remove leading/trailing whitespace from result
    result=$(echo "$result" | xargs)
    echo "$result"
}

echo "Prepare migration to 14.0..."

# Copy database
docker exec -u 70 "$DB_CONTAINER_NAME" pgm cp -f ou13 ou14@ou14

# Execute SQL pre-migration commands
PRE_MIGRATE_SQL=""
query_postgres_container "$PRE_MIGRATE_SQL"


# Copy filestores
rm -rf /srv/datastore/data/ou14/var/lib/odoo/filestore/ou14/* || exit 1
mkdir /srv/datastore/data/ou14/var/lib/odoo/filestore/ou14/* || exit 1
cp -a /srv/datastore/data/ou13/var/lib/odoo/filestore/ou13/* /srv/datastore/data/ou14/var/lib/odoo/filestore/ou14/ || exit 1

echo "Ready for migration to 14.0!"
