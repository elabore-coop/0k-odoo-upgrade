#!/bin/bash

####################
# GLOBAL VARIABLES #
####################

ORIGIN_VERSION="$1" # "12" for version 12.0
FINAL_VERSION="$2" # "16" for version 16.0
# Path to the database to migrate. Must be a .zip file with the following syntax: {DATABASE_NAME}.zip
ORIGIN_DB_NAME="$3"
ORIGIN_SERVICE_NAME="$4"

# Get origin database name
COPY_DB_NAME="ou${ORIGIN_VERSION}"
# Define finale database name
export FINALE_DB_NAME="ou${FINAL_VERSION}"
# Define finale odoo service name
FINALE_SERVICE_NAME="${FINALE_DB_NAME}"

# Service postgres name
export POSTGRES_SERVICE_NAME="lokavaluto_postgres_1"

#############################################
# DISPLAYS ALL INPUTS PARAMETERS
#############################################

echo "===== INPUT PARAMETERS ====="
echo "Origin version .......... $ORIGIN_VERSION"
echo "Final version ........... $FINAL_VERSION"
echo "Origin DB name ........... $ORIGIN_DB_NAME"
echo "Origin service name ..... $ORIGIN_SERVICE_NAME"

echo "
===== COMPUTED GLOBALE VARIABLES ====="
echo "Copy DB name ............. $COPY_DB_NAME"
echo "Finale DB name ........... $FINALE_DB_NAME"
echo "Finale service name ...... $FINALE_SERVICE_NAME"
echo "Postgres service name .... $POSTGRES_SERVICE_NAME"



# Function to launch an SQL request to the postgres container
query_postgres_container(){
    local QUERY="$1"
    local DB_NAME="$2"
    if [ -z "$QUERY" ]; then
	return 0
    fi
    local result
    if ! result=$(docker exec -u 70 "$POSTGRES_SERVICE_NAME" psql -d "$DB_NAME" -t -A -c "$QUERY"); then
        printf "Failed to execute SQL query: %s\n" "$query" >&2
        printf "Error: %s\n" "$result" >&2
        exit 1
    fi
    echo "$result"
}
export -f query_postgres_container

# Function to copy the postgres databases
copy_database(){
    local FROM_DB="$1"
    local TO_SERVICE="$2"
    local TO_DB="$3"
    docker exec -u 70 "$POSTGRES_SERVICE_NAME" pgm cp -f "$FROM_DB" "$TO_DB"@"$TO_SERVICE"
}
export -f copy_database

# Function to copy the filetores
copy_filestore(){
    local FROM_SERVICE="$1"
    local FROM_DB="$2"
    local TO_SERVICE="$3"
    local TO_DB="$4"
    mkdir -p /srv/datastore/data/"$TO_SERVICE"/var/lib/odoo/filestore/"$TO_DB" || exit 1
    rm -rf /srv/datastore/data/"$TO_SERVICE"/var/lib/odoo/filestore/"$TO_DB" || exit 1
    cp -a /srv/datastore/data/"$FROM_SERVICE"/var/lib/odoo/filestore/"$FROM_DB" /srv/datastore/data/"$TO_SERVICE"/var/lib/odoo/filestore/"$TO_DB" || exit 1
    echo "Filestore $FROM_SERVICE/$FROM_DB copied."
}
export -f copy_filestore

##############################################
# CHECKS ALL NEEDED COMPONENTS ARE AVAILABLE #
##############################################

echo "
==== CHECKS ALL NEEDED COMPONENTS ARE AVAILABLE ===="

# Check POSTGRES container is running
if ! docker ps | grep -q "$POSTGRES_SERVICE_NAME"; then
    printf "Docker container %s is not running.\n" "$POSTGRES_SERVICE_NAME" >&2
    return 1
else
    echo "UPGRADE: container $POSTGRES_SERVICE_NAME running."
fi

# Check origin database is in the local postgres
DB_EXISTS=$(docker exec -it -u 70 $POSTGRES_SERVICE_NAME psql -tc "SELECT 1 FROM pg_database WHERE datname = '$ORIGIN_DB_NAME'" | tr -d '[:space:]')
if [ "$DB_EXISTS" ]; then
    echo "UPGRADE: Database '$ORIGIN_DB_NAME' found."
else
    echo "ERROR: Database '$ORIGIN_DB_NAME' not found in the local postgress service. Please add it and restart the upgrade process."
    exit 1
fi

# Check that the origin filestore exist
REPERTOIRE="/srv/datastore/data/${ORIGIN_SERVICE_NAME}/var/lib/odoo/filestore/${ORIGIN_DB_NAME}"
if [ -d $REPERTOIRE ]; then
    echo "UPGRADE: '$REPERTOIRE' filestore found."
else
    echo "ERROR: '$REPERTOIRE' filestore not found, please add it and restart the upgrade process."
    exit 1
fi

#######################################
# LAUNCH VIRGIN ODOO IN FINAL VERSION #
#######################################

# Remove finale database and datastore if already exists (we need a virgin Odoo)
if docker exec -u 70 "$POSTGRES_SERVICE_NAME" pgm ls | grep -q "$FINALE_SERVICE_NAME"; then
    docker exec -u 70 "$POSTGRES_SERVICE_NAME" pgm rm -f "$FINALE_SERVICE_NAME"
    rm -rf /srv/datastore/data/"$FINALE_SERVICE_NAME"/var/lib/odoo/filestore/"$FINALE_SERVICE_NAME"
fi

compose --debug run "$FINALE_SERVICE_NAME" -i base --stop-after-init --no-http

echo "Model database in final Odoo version created."

############################
# COPY ORIGINAL COMPONENTS #
############################

echo "
==== COPY ORIGINAL COMPONENTS ===="
echo "UPGRADE: Start copy"

# Copy database
copy_database "$ORIGIN_DB_NAME" "$COPY_DB_NAME" "$COPY_DB_NAME" || exit 1
echo "UPGRADE: original database copied in ${COPY_DB_NAME}@${COPY_DB_NAME}."

# Copy filestore
copy_filestore "$ORIGIN_SERVICE_NAME" "$ORIGIN_DB_NAME" "$COPY_DB_NAME" "$COPY_DB_NAME" || exit 1
echo "UPGRADE: original filestore copied."


#####################
# PATH OF MIGRATION #
####################

echo "
==== PATH OF MIGRATION ===="
# List all the versions to migrate through
declare -a versions
nb_migrations=$(($FINAL_VERSION - $ORIGIN_VERSION))

# Build the migration path
for ((i = 0; i<$nb_migrations; i++))
do
    versions[$i]=$(($ORIGIN_VERSION + 1 + i))
done
echo "UPGRADE: Migration path is ${versions[@]}"


########################
# DATABASE PREPARATION #
########################

echo "
==== DATABASE PREPARATION ===="

./prepare_db.sh "$COPY_DB_NAME" "$COPY_DB_NAME" "$FINALE_DB_MODEL_NAME" "$FINALE_SERVICE_NAME" || exit 1


###################
# UPGRADE PROCESS #
###################

for version in "${versions[@]}"
do
    echo "START UPGRADE TO ${version}.0"
    start_version=$((version-1))
    end_version="$version"

    ### Go to the repository holding the upgrate scripts
    cd "${end_version}.0"

    ### Execute pre_upgrade scripts
    ./pre_upgrade.sh || exit 1

    ### Start upgrade
    ./upgrade.sh || exit 1

    ### Execute post-upgrade scripts
    ./post_upgrade.sh || exit 1

    ### Return to parent repository for the following steps
    cd ..
    echo "END UPGRADE TO ${version}.0"
done
## END UPGRADE LOOP

##########################
# POST-UPGRADE PROCESSES #
##########################
./finalize_db.sh "$FINALE_DB_NAME" "$FINALE_SERVICE_NAME" || exit 1


echo "UPGRADE PROCESS ENDED WITH SUCCESS"
