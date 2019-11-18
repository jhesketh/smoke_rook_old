#!/usr/bin/env bash

export JOB_ROOT=`dirname "$(realpath "$0")"`
export SMOKE_ROOK_ROOT=`realpath "$JOB_ROOT/../../../"`
source $SMOKE_ROOK_ROOT/common/common.sh

export DEV_ROOK_CEPH=$SMOKE_ROOK_ROOT/vendor/dev-rook-ceph

pushd $DEV_ROOK_CEPH
    make cluster.destroy
popd

rm -rf /tmp/test_node_addition
