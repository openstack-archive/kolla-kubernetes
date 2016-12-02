#!/bin/bash -xe

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"

export DISABLE_PULL=1
export OUTSIDE_GATE=1

$DIR/tests/bin/iscsi_workflow.sh dev-env centos 2
