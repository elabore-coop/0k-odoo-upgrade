# 0k-odoo-upgrade

## Installation

- Clone the current repo

## Configuration

- Requires to have the 0k scripts installed on the computer: https://git.myceliandre.fr/Lokavaluto/dev-pack

## Usage
### Before migration

- [ ] import the origin database to migrate on local computer
- [ ] Uninstall all useless Odoo add-ons. Warning: do not uninstall add-ons for which the disappearance in the finale version is managed by Open Upgrade scrips.
- [ ] Unsure all the add-ons are migrated in the final Odoo version
- [ ] (optional) De-active all the website views

### Local Migration process

- [ ] launch the origin database `ORIGIN_DATABASE_NAME` with original version of Odoo, with odoo service `ORIGIN_SERVICE`
- [ ] ensure you have a virgin database of the final version  already in your postgres service (`MODEL_FINAL_DATABASE_NAME`)
- [ ] launch the following command:

``` bash
./upgrade.sh {ORIGIN_VERSION} {DESTINATION_VERSION} {ORIGIN_DATABASE_NAME} {ORIGIN_SERVICE} {MODEL_FINAL_DATABASE_NAME}
```

ex: ./upgrade.sh 14 16 elabore_20241208 odoo14 ou16

### Deploy migrated base

- [ ] Retrieve the migrated database (vps odoo dump)
- [ ] Copy the database on the concerned VPS
- [ ] vps odoo restore


## Manage the add-ons to uninstall

The migration script will manage the uninstall of Odoo add-ons:
- add-ons we want to uninstall, whatever the reasons
- add-ons to uninstall because they do not exist in the final Odoo docker image

At the beginning of the process, the script compare the list of add-ons installed in the origin database, and the list of add-ons available in the `MODEL_FINAL_DATABASE`.

The whole list of add-ons to uninstall is displayed, and needs a confirmation before starting the migration.


## Manage migration issues

As the migration process is performed on a copy of the orginal database, the process can be restarted without limits.

Some Odoo migration errors won't stop the migration process, then be attentive to the errors in the logs.
