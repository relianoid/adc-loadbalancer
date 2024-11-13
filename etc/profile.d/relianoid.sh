#!/bin/bash

CLUSTER_STATUS=/etc/relianoid-ce-cluster.status

export PROMPT_COMMAND="\[ -f $CLUSTER_STATUS \] && echo -n \[\$(cat $CLUSTER_STATUS 2>/dev/null)\]\ "

