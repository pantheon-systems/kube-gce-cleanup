#!/bin/bash
# vim: ts=4:sw=4


#######################################
# Detects if this is a pod in a cluster, and validates that the passed in cluster
# is the cluster we are running in.
#
# If we are in a cluster set the KUBE_CONTEXT to a custom context representing
# the current cluster, and ignore any context passed in by the user.
#######################################
in_cluster_setup() {
    # if we are a pod in kube, this env var should exist, if not we just return since this func
    # is only meant to run if we are in a cluster
    if [[ -z "$KUBERNETES_SERVICE_HOST" ]] ; then
        return
    fi
    echo "Detected we are running in a kube pod."
    echo "Will run some checks before continuing."

    # Lets verify that our cluster == the name that someone passed in... Just in case
    meta_kube_cluster=$(curl http://169.254.169.254/computeMetadata/v1/instance/attributes/cluster-name -q -H "Metadata-Flavor: Google")
    if [[ "$GKE_CLUSTER_NAME" != "$meta_kube_cluster" ]] ; then
        echo "You said GKE_CLUSTER_NAME is '$GKE_CLUSTER_NAME' but Google metadata says it's '$meta_kube_cluster'"
        echo "In case this was a mistake we wont continue."
        exit 1
    fi

    # this is a hack to work around not having to do custom in/out of cluster kubectl commands
    # we ignore any supplied context when running in kube, and instead make our own
    echo "Creating a context for cluster"
    kubectl config set-context local-cluster --namespace=default
    KUBE_CONTEXT="local-cluster"
}

#######################################
# Check required environment is setup
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

# Check if the target pool has valid member nodes in the current cluster.
#
# Arguments:
#   targets - a list of nodes that are the pools target backends
#   current_nodes - the list of nodes that are currently backing the cluster
#
# Returns:
#   0 - the target-pool has nodes in use in the cluster
#   1 - the target-pool has no nodes backing it in the cluster
valid_target_pool() {
    local targets="$1"
    local current_nodes="$2"

    for i in $targets ; do
        # guard for the case where a target pool has targets not in this cluster
        if [[ ! "$i" =~ gke-${GKE_CLUSTER_NAME}.* ]] ; then
            echo " -> not in cluster, OK"
            return 0
        fi

        if grep -q "$i" <<<"$current_nodes"  ; then
            echo " -> nodes in use, OK"
            return 0
        fi
    done

    echo " -> No endpoints exist, DELETE"
    return 1
}

# check target pools for members that belong to the cluster, and also if they have
# a matching forwarding_rule for the project. If either there are no members or no
# forwarding rule then delete the firewall components for this rule.
#
# where we can we try to be as cautious as possible and scope these things to
# the specific cluster, but some kube managed gcloud objects don't have tags
# that indicate what cluster they belong to.
#
# in the case where we have a target pool that has no nodes, we will remove it.
# this can unexpectedly remove a target pool that actually was not belonging to the
# cluster if there are other clusters in the project. However a target pool without
# nodes isn't really active anyway
check_target_pools() {
    delete=()
    # filter node list to cluster nodes
    current_nodes=$(gcloud --project="$PROJECT" compute instances list --format='value(name)' --filter="name ~ ^gke-$GKE_CLUSTER_NAME" )

    # get all the current forwarding_rules so we can check if the target has valid forwarding rules
    current_forwarding_rules=$(gcloud --project="$PROJECT" compute forwarding-rules list --format='value(name)'  )

    # run over each target object in base64 encoded strings, we will decode and pull out the fields we are interested in
    # inside the loop, reducing the recursive calling to the slow gcloud api.
    for target in $(gcloud --project="$PROJECT" compute target-pools list --format='json' --filter="region:( $REGION )" | jq -r '.[] | @base64' ) ; do
        target_json=$(base64 --decode <<<"$target")
        target_name=$(jq -r '.name' <<<"$target_json" )

        echo "checking target $target_name"
        total=$(( total + 1 ))

        target_nodes=$(jq -r '.instances' <<<"$target_json"  | awk -F/  '{print $11}' | tr -d \" | tr -d , )
        if ! valid_target_pool "$target_nodes" "$current_nodes" ;  then
            echo " => no hosts in target pool; should delete"
            delete+=("$target_name")
            continue
        fi

        # check if theres a forwarding rule for this target pool, if not it's orphaned
        if ! grep -q "$target_name" <<<"$current_forwarding_rules"; then
            echo "=> no forwarding rule; should delete $target_name"
            delete+=("$target_name")
            continue
        fi
    done

    # we should return if we don't have anything to do
    if [[ ${#delete[@]} -le 0 ]] ; then
        return
    fi

    deleted=$(( deleted + ${#delete[@]} ))
    for i in "${delete[@]}" ; do
        if [[ -z "$DRYRUN" ]] ; then
            echo "DELETING target pool and associated objects $i"
            delete_gce_lb_objects "$i"
        fi
    done
}
