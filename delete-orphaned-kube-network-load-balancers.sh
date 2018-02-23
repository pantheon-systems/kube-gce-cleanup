#!/bin/bash
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

total=0
deleted=0
verb="should be deleted"

#######################################
# Check required enviroement is setup
#######################################
validate() {
  if [[ -z "$PROJECT" ]] || [[ -z "$REGION" ]] || [[ -z "$GKE_CLUSTER_NAME" ]] || [[ -z $KUBE_CONTEXT ]] ; then
    echo "Env vars must be set"
    echo "PROJECT:'$PROJECT'"
    echo "REGION:'$REGION'"
    echo "KUBE_CONTEXT:'$KUBE_CONTEXT'"
    echo "GKE_CLUSTER_NAME:'$GKE_CLUSTER_NAME'"
    exit 1
  fi
}

#######################################
# Determines if a gcloud firewall-rule is in use by the kubernetes cluster.
# Globals:
#   ACTIVE_IPS
# Arguments:
#   name of a gcloud firewall-rule resource
# Returns:
#   0 - the firewall-rule is in use
#   1 - the firewall-rule is not in use
#######################################
valid_firewall() {
  local id="$1"
  local fw_json description service_name ip

  fw_json=$(gcloud --project="${PROJECT}" compute firewall-rules describe "${id}" --format=json)
  description=$(jq -r .description <<<"$fw_json")
  service_name=$(jq -r '."kubernetes.io/service-name"' <<<"$description")
  ip=$(jq -r '."kubernetes.io/service-ip"' <<<"$description")

  echo "=> $id, IP: $ip, Service: $service_name"

  if ! grep -q "$ip" <<<"$ACTIVE_IPS"; then
    echo "  NOT in use by the kube cluster"
    return 1
  fi


  # does it have a valid front end
  echo "  IN USE by the kube cluster"
  return 0
}

#######################################
# Deletes all gcloud objects that represent a network load-balancer.
# A gcloud "network load-balancer" is not a single resource but 3 resources.
# Because kubernetes/GKE uses a similar name across all objects we are able to cleanup
# all resources given a single name.
# Globals:
#   PROJECT
#   REGION
# Arguments:
#   name - the gcloud name of the resources
# Returns:
#   None
#######################################
delete_gce_lb_objects() {
  local id="$1"

  # ignore failed deletions so that we can continue processing
  set +e
  gcloud compute "--project=${PROJECT}" -q firewall-rules   delete "k8s-fw-${id}"
  gcloud compute "--project=${PROJECT}" -q forwarding-rules delete "${id}"        "--region=${REGION}"
  gcloud compute "--project=${PROJECT}" -q target-pools     delete "${id}"        "--region=${REGION}"
  wait
  set -e
}

check_firewalls() {
  ACTIVE_IPS=$(kubectl --context="${KUBE_CONTEXT}" get services --all-namespaces -o json | jq -r '.items[].status.loadBalancer.ingress[0].ip' | sort | uniq)
  if [[ -z "$ACTIVE_IPS" ]]; then
    echo "ERROR: failed to get a list of public service IP's from the kube cluster"
    exit 1
  fi


  LIST=$(gcloud "--project=${PROJECT}" compute firewall-rules list \
    --format='value(name)' \
    --filter="name ~ ^k8s-fw- AND -tags gke-${GKE_CLUSTER_NAME}-")
  for x in ${LIST}; do
    if ! valid_firewall "$x"; then
      # extract the 32-char "id", ex: "k8s-fw-a018702dbb5d111e6bdee42010af0012" => "a018702dbb5d111e6bdee42010af0012"
      # since the other objects use only the id as their name while firewall-rules use a 'k8s-fw-' prefix for their name.
      local kube_id
      kube_id=$(sed 's/.*k8s-fw-\([a-z0-9]\{32\}\).*/\1/' <<<"${x}")

      if [[ -z "$DRYRUN" ]] ; then
        echo "  DELETING $kube_id, this will take several minutes ..."
        delete_gce_lb_objects "$kube_id"
      fi
      deleted=$((deleted + 1))
    fi
    total=$((total + 1))
  done

}

valid_target_pool() {
  targets=$1
  for i in $targets ; do
    if grep -q "$targets" <<<"$current_nodes" ; then
      #echo " -> target node $i in use!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      return 0
    fi
  done
  #echo " -> No endpoints exist for this target"
  return 1
}

check_target_pools() {
  delete=()

  current_nodes=$(gcloud --project="$PROJECT" compute instances list --format='value(name)' )
  targets=$(gcloud --project="$PROJECT" compute target-pools list --format='value(name)' --filter="region:( $REGION )")
  current_forwarding_rules=$(gcloud --project="$PROJECT" compute forwarding-rules list --format='value(name)'  )
  for tp in $targets ; do
    echo "checking target $tp"
    total=$(( total + 1 ))

    target_nodes=$(gcloud --project="$PROJECT" compute target-pools describe "$tp" --region="$REGION"  | grep zone | grep instances | awk -F/  '{print $11}')
    if ! valid_target_pool "$target_nodes"; then
      echo " => no hosts in target pool; should delete"
      delete+=("$tp")
      continue
    fi

    # check if theres a forwarding rule for this target pool, if not it's orphaned
    if ! grep -q "$tp" <<<"$current_forwarding_rules"; then
      echo "=> no forwarding rule; should delete $tp"
      delete+=("$tp")
      continue
    fi
  done
  deleted=$(( deleted + ${#delete[@]} ))

  for i in "${delete[@]}" ; do
    if [[ -z "$DRYRUN" ]] ; then
      echo "DELETING target pool and associated objects $i"
      delete_gce_lb_objects "$i"
    fi
  done
}

main() {
  if [[ -z "$DRYRUN" ]] ; then
    verb="Deleted"
  fi

  validate
  check_target_pools
  check_firewalls

  echo "$verb: $deleted"
  echo "scanned: $total"
}

main
