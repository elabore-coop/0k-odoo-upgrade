#!/bin/bash

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
query_postgres_container "$PRE_MIGRATE_SQL" ou15 || exit 1


# Copy filestores
rm -rf /srv/datastore/data/ou15/var/lib/odoo/filestore/ou15 || exit 1
cp -a /srv/datastore/data/ou14/var/lib/odoo/filestore/ou14 /srv/datastore/data/ou15/var/lib/odoo/filestore/ou15 || exit 1

echo "Ready for migration to 15.0!"
