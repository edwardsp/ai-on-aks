#!/bin/bash

CONF_FILE=/azure-nhc/conf/aznhc.conf
LOG_FILE=/azure-nhc/aznhc.log

nhc DETACHED_MODE=0 CONFFILE=$CONF_FILE LOGFILE=$LOG_FILE TIMEOUT=300

# annotate node with test results
kubectl annotate node $NODE_NAME aznhc-results="$(<$LOG_FILE)" --overwrite

if grep -q "ERROR:  nhc:  Health check failed:" $LOG_FILE; then
    kubectl taint nodes "$NODE_NAME" aznhc=failed:NoSchedule
    ## label node as unhealthy
    #kubectl label node $NODE_NAME aznhc=failed --overwrite
    exit 1
fi

## label node as healthy
#kubectl label node $NODE_NAME aznhc=success --overwrite
#exit 0

