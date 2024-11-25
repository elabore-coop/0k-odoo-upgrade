#!/bin/bash

# Global variables
ODOO_SERVICE="$1"
DB_NAME="$2"
DB_FINALE_MODEL="$3"
DB_FINALE_SERVICE="$4"
DB_CONTAINER_NAME="lokavaluto_postgres_1"

# Function to launch an SQL request to the postgres container
query_postgres_container(){
    local query="$1"
    if [ -z "$query" ]; then
	return 0
    fi
    local result
    if ! result=$(docker exec -u 70 $DB_CONTAINER_NAME psql -d $DB_NAME -t -A -c "$query" 2>&1); then
        printf "Failed to execute SQL query: %s\n" "$query" >&2
        printf "Error: %s\n" "$result" >&2
        exit 1
    fi
    # Remove leading/trailing whitespace from result
    result=$(echo "$result" | xargs)
    echo "$result"
}


# Function to display the combined list of add-ons to uninstall
display_combined_list(){
    cat 404_addons force_uninstall_addons > combined_addons
    echo "UPGRADE: Add-ons to uninstall (forced and not found in final Odoo version):"
    cat combined_addons
}

# Function to ask if the add-ons list to uninstall is OK
ask_confirmation() {
    while true; do
        echo "
Do you accept to uninstall all these add-ons? (Y/N/R)"
        echo "Y - Yes, let's go on with the upgrade."
        echo "N - No, stop the upgrade"
        echo "R - I've edited the list, please Re-display it"
        read -p "Your choice: " choice
        case $choice in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            [Rr]* ) display_combined_list; continue;;
            * ) echo "Please answer by Y, N or R.";;
        esac
    done
}

# Read names from file and create SQL commands
generate_sql_to_remove_commands() {
    local name
    local sql_commands=""
    while IFS= read -r name; do
        sql_commands+="UPDATE ir_module_module SET to_remove = TRUE WHERE name = '$name';"
    done < combined_addons
    echo "$sql_commands"
}

# Main execution
echo "UPGRADE: Start database preparation"

# Check POSTGRES container is running
if ! docker ps | grep -q "$DB_CONTAINER_NAME"; then
    printf "Docker container %s is not running.\n" "$DB_CONTAINER_NAME" >&2
    return 1
fi

EXT_EXISTS=$(query_postgres_container "SELECT 1 FROM pg_extension WHERE extname = 'dblink'")
if [ "$EXT_EXISTS" != "1" ]; then
    query_postgres_container "CREATE EXTENSION dblink;"
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
query_postgres_container "$SQL_NEUTRALIZE"

################################
## Uninstall unwished add-ons ##
################################

# Add columns to_remove and dependencies
SQL_INIT=$(cat <<'EOF'
ALTER TABLE ir_module_module ADD COLUMN IF NOT EXISTS to_remove BOOLEAN;
ALTER TABLE ir_module_module ADD COLUMN IF NOT EXISTS dependencies VARCHAR;
UPDATE ir_module_module SET state = 'installed' WHERE state = 'to_remove';
UPDATE ir_module_module SET to_remove = false;
UPDATE ir_module_module SET dependencies = '';
EOF
)
query_postgres_container "$SQL_INIT"


# List add-ons not available on the final Odoo version
SQL_404_ADDONS_LIST="
	SELECT module_origin.name
	FROM ir_module_module module_origin
	LEFT   JOIN (
	   SELECT *
	   FROM   dblink('dbname=$DB_FINALE_MODEL','SELECT name, shortdesc, author FROM ir_module_module')
	   AS     tb2(name text, shortdesc text, author text)
	) AS module_dest ON module_dest.name = module_origin.name

	WHERE (module_dest.name IS NULL) AND (module_origin.state = 'installed') AND (module_origin.author NOT IN ('Odoo S.A.', 'Lokavaluto', 'Elabore'))
	ORDER BY module_origin.name
;
"
query_postgres_container "$SQL_404_ADDONS_LIST" > 404_addons


# Ask confirmation to uninstall the selected add-ons
display_combined_list


if ask_confirmation; then
    echo "Upgrade goes on..."
else
    echo "Upgrade stopped."
    exit 1
fi



# Tag the selected add-ons as "to remove"
echo "TAG the add-ons to remove..."
SQL_TAG_TO_REMOVE=""
while IFS= read -r name; do
    SQL_TAG_TO_REMOVE+="UPDATE ir_module_module SET to_remove = TRUE WHERE name = '$name' AND state = 'installed';"
done < combined_addons
query_postgres_container "$SQL_TAG_TO_REMOVE"
echo "Add-ons to be removed TAGGED."


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
    updated=$(query_postgres_container "$SQL_DEPENDENCIES")
done;
echo "All dependencies to remove TAGGED"


# Change state of add-ons to remove
echo "Change state of all add-ons to remove..."
SQL_UPDATE_STATE="UPDATE ir_module_module SET state = 'to remove' WHERE to_remove = TRUE AND state = 'installed';"
query_postgres_container "$SQL_UPDATE_STATE"
echo "Add-ons to remove with state 'to_remove'"


# Launch Odooo container and launch the uninstall function
echo "Launch Odoo to uninstall add-ons..."
echo "print('START ADD-ONS UNINSTALL'); self.env['ir.module.module'].search([('state', '=', 'to remove')]).button_immediate_uninstall(); print('END ADD-ONS UNINSTALL')" | compose run $ODOO_SERVICE shell --database=$DB_NAME --no-http
echo "Add-ons uninstall successful."
