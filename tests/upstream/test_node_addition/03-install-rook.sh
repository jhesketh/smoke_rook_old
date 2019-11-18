#!/usr/bin/env bash

export JOB_ROOT=`dirname "$(realpath "$0")"`
export SMOKE_ROOK_ROOT=`realpath "$JOB_ROOT/../../../"`
source $SMOKE_ROOK_ROOT/common/common.sh

export DEV_ROOK_CEPH=$SMOKE_ROOK_ROOT/vendor/dev-rook-ceph

pushd $DEV_ROOK_CEPH
    mkdir -p /tmp/test_node_addition
    mkdir -p /tmp/test_node_addition/go/src/github.com/rook
    
    pushd /tmp/test_node_addition/go/src/github.com/rook
        git clone https://github.com/rook/rook
    popd

    export GOPATH=/tmp/test_node_addition/go

    make rook.build
    make rook.install
popd
