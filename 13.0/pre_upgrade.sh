#!/bin/bash

DB_CONTAINER_NAME="lokavaluto_postgres_1"

# Function to launch an SQL request to the postgres container
query_postgres_container(){
    local query="$1"
    if [ -z "$query" ]; then
	return 0
    fi
    local result
    if ! result=$(docker exec -u 70 "$DB_CONTAINER_NAME" psql -d ou13 -t -A -c "$query" 2>&1); then
        printf "Failed to execute SQL query: %s\n" "$query" >&2
        printf "Error: %s\n" "$result" >&2
        exit 1
    fi
    # Remove leading/trailing whitespace from result
    result=$(echo "$result" | xargs)
    echo "$result"
}

echo "Prepare migration to 13.0..."

# Copy database
docker exec -u 70 "$DB_CONTAINER_NAME" pgm cp -f ou12 ou13@ou13

# Execute SQL pre-migration commands
PRE_MIGRATE_SQL=$(cat <<'EOF'
/* Add analytic_policy column as openupgrade script is waiting for it whereas it doesn't existe since v12.  */
ALTER TABLE public.account_account_type ADD analytic_policy varchar NULL;

/* The model in missing on some website_sale data */
UPDATE ir_model_data SET model = 'ir.ui.view' WHERE module = 'website_sale' AND name = 'recommended_products';
UPDATE ir_model_data SET model = 'ir.ui.view' WHERE module = 'website_sale' AND name = 'product_comment';
EOF
)
query_postgres_container "$PRE_MIGRATE_SQL"


# Copy filestores
rm -rf /srv/datastore/data/ou13/var/lib/odoo/filestore/ou13 || exit 1
cp -a /srv/datastore/data/ou12/var/lib/odoo/filestore/ou12 /srv/datastore/data/ou13/var/lib/odoo/filestore/ou13 || exit 1

echo "Ready for migration to 13.0!"
