#!/bin/bash

####################
# GLOBAL VARIABLES #
####################

ORIGIN_VERSION="$1" # "12" for version 12.0
FINAL_VERSION="$2" # "16" for version 16.0
# Path to the database to migrate. Must be a .zip file with the following syntax: {DATABASE_NAME}.zip
ORIGIN_DATABASE_PATH="$3"
ORIGIN_SERVICE_NAME="$4"
FINALE_DB_MODEL_NAME="$5" #To check the add-ons available in the finale version


# Get origin database name
ORIGIN_DB_NAME=$(basename "$ORIGIN_DATABASE_PATH" .zip)
COPY_DB_NAME="ou${ORIGIN_VERSION}"
# Define finale database name
FINALE_DB_NAME="ou${FINAL_VERSION}"
# Define finale odoo service name
FINALE_SERVICE_NAME="${FINALE_DB_NAME}"

# Service postgres name
POSTGRES_SERVICE_NAME="lokavaluto_postgres_1"

#############################################
# DISPLAYS ALL INPUTS PARAMETERS
#############################################

echo "===== INPUT PARAMETERS ====="
echo "Origin version .......... $ORIGIN_VERSION"
echo "Final version ........... $FINAL_VERSION"
echo "Origin database path .... $ORIGIN_DATABASE_PATH"
echo "Origin service name ..... $ORIGIN_SERVICE_NAME"
echo "Finale DB model name .... $FINALE_DB_MODEL_NAME"

echo "
===== COMPUTED GLOBALE VARIABLES ====="
echo "Origin DB name ........... $ORIGIN_DB_NAME"
echo "Copy DB name ............. $COPY_DB_NAME"
echo "Finale DB name ........... $FINALE_DB_NAME"
echo "Finale service name ...... $FINALE_SERVICE_NAME"
echo "Postgres service name .... $POSTGRES_SERVICE_NAME"


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

# Check final version database model is in the local postgres
DB_EXISTS=$(docker exec -it -u 70 $POSTGRES_SERVICE_NAME psql -tc "SELECT 1 FROM pg_database WHERE datname = '$FINALE_DB_MODEL_NAME'" | tr -d '[:space:]')
if [ "$DB_EXISTS" ]; then
    echo "UPGRADE: Database '$FINALE_DB_MODEL_NAME' found."
else
    echo "ERROR: Database '$FINALE_DB_MODEL_NAME' not found in the local postgress service. Please add it and restart the upgrade process."
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



############################
# COPY ORIGINAL COMPONENTS #
############################

echo "
==== COPY ORIGINAL COMPONENTS ===="
echo "UPGRADE: Start copy"

# Copy database
docker exec -u 70 $POSTGRES_SERVICE_NAME pgm cp -f "$ORIGIN_DB_NAME" "${COPY_DB_NAME}@${COPY_DB_NAME}" || exit 1
echo "UPGRADE: original database copied in ${COPY_DB_NAME}@${COPY_DB_NAME}."

# Copy filestore
rm -rf /srv/datastore/data/${COPY_DB_NAME}/var/lib/odoo/filestore/${COPY_DB_NAME} || exit 1
cp -a /srv/datastore/data/$ORIGIN_SERVICE_NAME/var/lib/odoo/filestore/$ORIGIN_DB_NAME /srv/datastore/data/$COPY_DB_NAME/var/lib/odoo/filestore/$COPY_DB_NAME || exit 1

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

source prepare_db.sh "$COPY_DB_NAME" "$COPY_DB_NAME" "$FINALE_DB_MODEL_NAME" "$FINALE_SERVICE_NAME"


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
    source ./pre_upgrade.sh

    ### Start upgrade
    source ./upgrade.sh

    ### Execute post-upgrade scripts
    source ./post_upgrade.sh

    ### Return to parent repository for the following steps
    cd ..
    echo "END UPGRADE TO ${version}.0"
done
## END UPGRADE LOOP

##########################
# POST-UPGRADE PROCESSES #
##########################
source finalize_db.sh "$FINALE_DB_NAME" "$FINALE_SERVICE_NAME"


echo "UPGRADE PROCESS ENDED WITH SUCCESS"
