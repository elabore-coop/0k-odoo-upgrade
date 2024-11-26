#!/bin/bash

echo "Prepare migration to 16.0..."

# Copy database
copy_database ou15 ou16 ou16 || exit 1

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
query_postgres_container "$PRE_MIGRATE_SQL" ou16 || exit 1

# Copy filestores
copy_filestore ou15 ou15 ou16 ou16 || exit 1

echo "Ready for migration to 16.0!"
