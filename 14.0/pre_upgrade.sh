#!/bin/bash

echo "Prepare migration to 14.0..."

# Copy database
docker exec -u 70 "$DB_CONTAINER_NAME" pgm cp -f ou13 ou14@ou14

# Execute SQL pre-migration commands
PRE_MIGRATE_SQL=""
query_postgres_container "$PRE_MIGRATE_SQL" ou14 || exit 1


# Copy filestores
rm -rf /srv/datastore/data/ou14/var/lib/odoo/filestore/ou14 || exit 1
cp -a /srv/datastore/data/ou13/var/lib/odoo/filestore/ou13 /srv/datastore/data/ou14/var/lib/odoo/filestore/ou14 || exit 1

echo "Ready for migration to 14.0!"
