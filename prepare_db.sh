#!/bin/bash

# Global variables
ODOO_SERVICE="$1"
DB_NAME="$2"
DB_FINALE_MODEL="$3"
DB_FINALE_SERVICE="$4"

# Function to ask if the add-ons list to uninstall is OK
ask_confirmation() {
    while true; do
        echo "
Do you accept to uninstall all these add-ons? (Y/N/R)"
        echo "Y - Yes, let's go on with the upgrade."
        echo "N - No, stop the upgrade"
        read -n 1 -p "Your choice: " choice
        case "$choice" in
            [Yy] ) echo "
Upgrade confirmed!"; return 0;;
            [Nn] ) echo "
Upgrade cancelled!"; return 1;;
            * ) echo "Please answer by Y or N.";;
        esac
    done
}

# Main execution
echo "UPGRADE: Start database preparation"

# Check POSTGRES container is running
if ! docker ps | grep -q "$DB_CONTAINER_NAME"; then
    printf "Docker container %s is not running.\n" "$DB_CONTAINER_NAME" >&2
    return 1
fi

EXT_EXISTS=$(query_postgres_container "SELECT 1 FROM pg_extension WHERE extname = 'dblink'" "$DB_NAME") || exit 1
if [ "$EXT_EXISTS" != "1" ]; then
    query_postgres_container "CREATE EXTENSION dblink;" "$DB_NAME" || exit 1
fi

# Neutralize the database
SQL_NEUTRALIZE=$(cat <<'EOF'
/* Archive all the mail servers */
UPDATE fetchmail_server SET active = false;
UPDATE ir_mail_server SET active = false;

/* Archive all the cron */
ALTER TABLE ir_cron ADD COLUMN IF NOT EXISTS active_bkp BOOLEAN;
UPDATE ir_cron SET active_bkp = active;
UPDATE ir_cron SET active = False;
EOF
	      )
echo "Neutralize base..."
query_postgres_container "$SQL_NEUTRALIZE" "$DB_NAME" || exit 1
echo "Base neutralized..."

################################
## Uninstall unwished add-ons ##
################################

# Add columns to_remove and dependencies
SQL_INIT=$(cat <<'EOF'
ALTER TABLE ir_module_module ADD COLUMN IF NOT EXISTS to_remove BOOLEAN;
ALTER TABLE ir_module_module ADD COLUMN IF NOT EXISTS dependencies VARCHAR;
UPDATE ir_module_module SET state = 'installed' WHERE state = 'to remove';
UPDATE ir_module_module SET to_remove = false;
UPDATE ir_module_module SET dependencies = '';
EOF
)
echo "Prepare ir.module table"
query_postgres_container "$SQL_INIT" "$DB_NAME" || exit 1


# List add-ons not available on the final Odoo version
SQL_404_ADDONS_LIST="
	SELECT module_origin.name
	FROM ir_module_module module_origin
	LEFT   JOIN (
	   SELECT *
	   FROM   dblink('dbname=$FINALE_DB_NAME','SELECT name, shortdesc, author FROM ir_module_module')
	   AS     tb2(name text, shortdesc text, author text)
	) AS module_dest ON module_dest.name = module_origin.name

	WHERE (module_dest.name IS NULL) AND (module_origin.state = 'installed') AND (module_origin.author NOT IN ('Odoo S.A.', 'Lokavaluto', 'Elabore'))
	ORDER BY module_origin.name
;
"
echo "Retrieve 404 addons... "
query_postgres_container "$SQL_404_ADDONS_LIST" "$DB_NAME" > 404_addons || exit 1

# Create combined list of add-ons not found and add-ons which must be removed
cat 404_addons force_uninstall_addons | sort | uniq > combined_addons

# Keep only the installed add-ons
INSTALLED_ADDONS="SELECT name FROM ir_module_module WHERE state='installed';"
query_postgres_container "$INSTALLED_ADDONS" "$DB_NAME" > installed_addons || exit 1

grep -Fx -f combined_addons installed_addons > addons_to_remove
rm -f 404_addons combined_addons installed_addons

# Ask confirmation to uninstall the selected add-ons
echo "
==== FIRST CHECK ====
Installed add-ons to uninstall (forced OR not found in final Odoo version):
"
cat addons_to_remove
ask_confirmation || exit 1

# Tag the selected add-ons as "to remove"
echo "TAG the add-ons to remove..."
SQL_TAG_TO_REMOVE=""
while IFS= read -r name; do
    SQL_TAG_TO_REMOVE+="UPDATE ir_module_module SET to_remove = TRUE WHERE name = '$name' AND state = 'installed';"
done < addons_to_remove
echo $SQL_TAG_TO_REMOVE
query_postgres_container "$SQL_TAG_TO_REMOVE" "$DB_NAME" || exit 1
echo "Add-ons to be removed TAGGED."

rm -f addons_to_remove

# Identify the add-ons which depend on the add-on to uninstall
echo "Detect and tag add-ons dependencies..."
SQL_DEPENDENCIES="
		 UPDATE ir_module_module imm SET to_remove = true, dependencies = immd.name
		 FROM ir_module_module_dependency immd
		 WHERE immd.module_id = imm.id AND imm.state = 'installed' AND imm.to_remove = false
		 AND immd.name IN (
		 	SELECT name FROM ir_module_module WHERE to_remove = True
		 );
"
updated=""
while [[ "$updated" != "UPDATE 0" ]]; do
    updated=$(query_postgres_container "$SQL_DEPENDENCIES" "$DB_NAME") || exit 1
done;
echo "All dependencies to remove TAGGED"


# Change state of add-ons to remove
echo "Change state of all add-ons to remove..."
SQL_UPDATE_STATE="UPDATE ir_module_module SET state = 'to remove' WHERE to_remove = TRUE AND state = 'installed';"
query_postgres_container "$SQL_UPDATE_STATE" "$DB_NAME" || exit 1
echo "Add-ons to remove with state 'to remove'"

# Last check on all the add-ons to be removed
echo "
==== LAST CHECK! ====
Here is the whole list of add-ons to be removed:
"
SQL_ADDONS_TO_BE_REMOVED="SELECT name from ir_module_module WHERE state='to remove';"
query_postgres_container "$SQL_ADDONS_TO_BE_REMOVED" "$DB_NAME" || exit 1
ask_confirmation || exit 1


# Launch Odooo container and launch the uninstall function
echo "Launch Odoo to uninstall add-ons..."
echo "print('START ADD-ONS UNINSTALL'); self.env['ir.module.module'].search([('state', '=', 'to remove')]).button_immediate_uninstall(); print('END ADD-ONS UNINSTALL')" | compose run $ODOO_SERVICE shell --database=$DB_NAME --no-http
echo "Add-ons uninstall successful."
