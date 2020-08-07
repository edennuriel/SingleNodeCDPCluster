#!/bin/bash
##
# Copyright (c) 2017 Cloudera, Inc. All rights reserved.
##
set -x

PROCESS_DIR=$(dirname $(dirname $(readlink -f $0)))

# convert cdsw.properties to environment file expected by CDSW by putting the
# values in quotes and escaping wherever required
# The environment file also contains the KUBE_TOKEN generated out of CDSW_SECRET
# defined in the properties file and JAVA_HOME picked from the environment.
python ${PROCESS_DIR}/scripts/generate_conf.py >${PROCESS_DIR}/cdsw.conf

export CDSW_ROOT=$PARCELS_ROOT/CDSW
export ENABLE_SHELL_DEBUG_MODE=${ENABLE_SHELL_DEBUG_MODE:=true}

CSD_VERSION=$(cat "$CONF_DIR/meta/cdsw_version")
PARCEL_VERSION=$(cat $CDSW_ROOT/meta/parcel.json | python -c "import sys, json; print json.load(sys.stdin)['version']" | sed -e 's/\(.*\).p.*/\1/')

if [ "$CSD_VERSION" != "$PARCEL_VERSION" ]; then
  echo "**********"
  echo "* The CSD version ($CSD_VERSION) is not compatible with the current"
  echo "* CDSW version ($PARCEL_VERSION). Either update your CSD or        "
  echo "* make sure you have the correct CDSW version installed and        "
  echo "* activated.                                                       "
  echo "**********"
  exit 1
fi

case $1 in

  start_app)
    exec ${CDSW_ROOT}/cdsw_admin/scripts/start_admin.sh
    ;;

  stop_app)
    exec ${CDSW_ROOT}/cdsw_admin/scripts/stop_admin.sh
    ;;

  start_kubelet_master)
    exec $CDSW_ROOT/scripts/start-kubelet-master-standalone.sh
    ;;

  stop_kubelet_master)
    exec $CDSW_ROOT/scripts/stop-kubelet-standalone.sh
    ;;

  start_kubelet_worker)
    exec $CDSW_ROOT/scripts/start-kubelet-worker-standalone.sh
    ;;

  stop_kubelet_worker)
    exec $CDSW_ROOT/scripts/stop-kubelet-standalone.sh
    ;;

  start_docker)
    exec $CDSW_ROOT/scripts/start-dockerd-standalone.sh
    ;;

  stop_docker)
    exec $CDSW_ROOT/scripts/stop-dockerd-standalone.sh
    ;;

  prepare_node)
    exec $CDSW_ROOT/scripts/prepare-node.sh $2
    ;;

  status)
    exec $CDSW_ROOT/scripts/cdsw-status.sh
    ;;

  validate)
    exec $CDSW_ROOT/scripts/cdsw-validate.sh
    ;;

  diagnostics)
    source ${PROCESS_DIR}/cdsw.conf
    MAX_BUNDLE_SIZE=10485760 # 10MB

    HOSTNAME=$(hostname -s)
    TIMESTAMP="$(date +%Y-%m-%d--%H-%M-%S)"
    export LOG_NAME="cdsw-support_bundle-$HOSTNAME-$TIMESTAMP"

    LOGS_STAGING_DIR=${LOGS_STAGING_DIR:-"/var/lib/cdsw/tmp"}
    mkdir -p $LOGS_STAGING_DIR
    rm -rf $LOGS_STAGING_DIR/*

    LOGS_MAX_LINES_PER_CONTAINER=${LOGS_MAX_LINES_PER_CONTAINER:-"1000"}
    (cd $LOGS_STAGING_DIR && $CDSW_ROOT/scripts/cdsw-logs.sh -l ${LOGS_MAX_LINES_PER_CONTAINER})

    rm -f "$LOGS_STAGING_DIR/$LOG_NAME.tar.gz" || true
    ACTUAL_SIZE=$(wc -c <"$LOGS_STAGING_DIR/$LOG_NAME.redacted.tar.gz")
    if [ $ACTUAL_SIZE -ge $MAX_BUNDLE_SIZE ]; then
      MESSAGE="ERROR: The Cloudera Data Science Workbench diagnostic bundle was deleted as it exceeded the maximum allowed size (${ACTUAL_SIZE}/${MAX_BUNDLE_SIZE})."
      echo $MESSAGE
      echo $MESSAGE >error.txt
      rm -f "$LOGS_STAGING_DIR/$LOG_NAME.redacted.tar.gz"
      tar cvzf support_bundle_empty.tar.gz error.txt
      ln -s ${PROCESS_DIR}/support_bundle_empty.tar.gz output.gz
    else
      ln -s ${LOGS_STAGING_DIR}/$LOG_NAME.redacted.tar.gz output.gz
    fi
    exit 0
    ;;

  *)
    echo "Don't understand [$1]"
    exit 1
    ;;

esac
