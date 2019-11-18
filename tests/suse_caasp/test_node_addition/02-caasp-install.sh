#!/usr/bin/env bash

export JOB_ROOT=`dirname "$(realpath "$0")"`
export SMOKE_ROOK_ROOT=`realpath "$JOB_ROOT/../../../"`
source $SMOKE_ROOK_ROOT/common/common.sh

# Install caasp with skuba