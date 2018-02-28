#!/bin/bash
# vim: ts=4:sw=4
#
# A utility for deleting google cloud network load-balancers that are unattached to active
# kubernetes' services.
#
# This script is necessary due to bugs in GKE/Kubernetes right now (Feb 2017) that prevent
# gcloud load-balancer resource objects from being cleaned up properly.
#
# Note that a google "load-balancer" is not a single object, it is a combination of 3 objects:
# firewall-rule / forwarding-rule / target-pool. This script will try to delete all related objects.
# the objects following a common naming pattern so they're able to be linked by name.
#
# References:
# - (kube issue cited by google support): https://github.com/kubernetes/kubernetes/issues/4630
#
# USAGE:
#
#   $ PROJECT=fooproject \
#     REGION=us-central1 \
#     GKE_CLUSTER_NAME=cluster-01 \
#   ./delete-orphaned-kube-network-resources.sh

set -eou pipefail
DRYRUN=${DRYRUN:-}
PROJECT=${PROJECT:-}
REGION=${REGION:-}
KUBE_CONTEXT=${KUBE_CONTEXT:-}
GKE_CLUSTER_NAME=${GKE_CLUSTER_NAME:-}
KUBERNETES_SERVICE_HOST=${KUBERNETES_SERVICE_HOST:-}

total=0
deleted=0
verb="should be deleted"

source lib/delete-orphans.bash

main() {
    if [[ -z "$DRYRUN" ]] ; then
        verb="Deleted"
    fi

    in_cluster_setup
    validate
    check_target_pools
    check_firewalls

    echo "$verb: $deleted"
    echo "scanned: $total"
}

main
