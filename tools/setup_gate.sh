#!/bin/bash -xe

# test

PACKAGE_VERSION=0.7.0-1
DISTRO="$2"
TYPE="$3"
CONFIG="$4"
BRANCH="$7"
PIPELINE="$8"

trap 'tests/bin/gate_capture_logs.sh "$?"' ERR
mkdir -p $WORKSPACE/logs/
env > $WORKSPACE/logs/env

if [ "x$PIPELINE" == "xperiodic" ]; then
    mkdir -p $WORKSPACE/UPLOAD_CONTAINERS
fi

case "$BRANCH" in
   "3" ) 
       sed -i 's/2\.0\.2/3.0.2/g' helm/all_values.yaml
       sed -i 's/2\.0\.2/3.0.2/g' tests/conf/ceph-all-in-one/kolla_config
       sed -i 's/cell_enabled.*/cell_enabled: false/g' helm/service/nova-control/values.yaml
       sed -i 's/cell_enabled.*/cell_enabled: false/g' helm/service/nova-compute/values.yaml
       ;;
   "4" )
       sed -i 's/2\.0\.2/4.0.0/g' helm/all_values.yaml
       sed -i 's/2\.0\.2/4.0.0/g' tests/conf/ceph-all-in-one/kolla_config
       ;;
   "t" )
       echo Version: $BRANCH is not implemented yet.
       exit 1
       ;;
   "*" )
       echo Still on 2.0.0 images
       sed -i 's/cell_enabled.*/cell_enabled: false/g' helm/service/nova-control/values.yaml
       sed -i 's/cell_enabled.*/cell_enabled: false/g' helm/service/nova-compute/values.yaml
       ;;
esac

#
# If TYPE is 'source', kolla_install_type 'source' must be added
# to kolla_config, to generate source based configs and not binary
# which is default.
#
if [ "x$TYPE" == "xsource" ]; then
    for kolla_config in tests/conf/ceph-all-in-one/kolla_config \
                        tests/conf/iscsi-all-in-one/kolla_config ; do
        if [ "x$(grep kolla_install_type $kolla_config)" == "x" ]; then
           sed -i '1s/^/kolla_install_type: source\n/' $kolla_config
        else
           sed -i 's/kolla_install_type.*/kolla_install_type: source/g' $kolla_config
        fi
    done
    sed -i 's/install_type.*/install_type: source/g' helm/all_values.yaml 
fi

if [ "x$4" == "xiscsi" ]; then
    tools/setup_gate_iscsi.sh $1 $2 $3 $4 $5 $BRANCH $PIPELINE
    exit 0
fi

if [ "x$4" == "xhelm-operator" ]; then
    echo "Not yet implemented..."  "$CONFIG" "$DISTRO" "$BRANCH"
    exit 1
fi

if [ "x$4" == "xhelm-compute-kit" ]; then
    tools/setup_gate_iscsi.sh $1 $2 $3 $4 $5 $BRANCH $PIPELINE
    exit 0
fi

if [ "x$4" == "xironic" ]; then
    tools/setup_gate_iscsi.sh $1 $2 $3 $4 $5 $BRANCH $PIPELINE
    exit 0
fi

#
# Starting default config CEPH
#

echo "1 "$1 "2 "$2 "3 "$3 "4 "$4 "5 "$5 "BRANCH "$BRANCH "PIPELINE "$PIPELINE
tools/setup_gate_ceph.sh $1 $2 $3 $4 $5 $BRANCH $PIPELINE
exit 0
