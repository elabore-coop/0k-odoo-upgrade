#!/bin/bash

compose -f ../compose.yml run -p 8015:8069 ou15 --config=/opt/odoo/auto/odoo.conf --stop-after-init -u all --workers 0 --log-level=warn --max-cron-threads=0 --limit-time-real=10000 --database=ou15 --load=web,openupgrade_framework
