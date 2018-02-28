#!/usr/bin/env bats
load ../lib/delete-orphans

load helpers/targets

GKE_CLUSTER_NAME="foocluster-01"

# the happy path things are in teh cluster should be a keep
@test "inside of cluster" {
  run valid_target_pool  "$foo_targets"  "$foo_current"
  echo "output = ${output}"
  [ "$status" -eq 0 ]
}

# empty targets should mean delete
@test "empty targets" {
  run valid_target_pool  ""  "$foo_current"
  echo "output = ${output}"
  [ "$status" -eq 1 ]
}

# orphaned nodes should mean delete
@test "orphan nodes" {
  local targets=$(cat <<EOF
gke-foocluster-01-orphan
gke-foocluster-01-orphan2
EOF
)

  run valid_target_pool "$targets" "$foo_current"
  echo "output = ${output}"
  [ "$status" -eq 1 ]
}

# mixed orpahn + real  should mean keep
@test "real + orphan nodes" {
  local targets=$(cat <<EOF
gke-foocluster-01-1
gke-foocluster-01-orphan
EOF
)

  run valid_target_pool "$targets" "$foo_current"
  echo "output = ${output}"
  [ "$status" -eq 0 ]
}

# should keep if its got nodes outside current cluster
@test "outside of cluster" {
  GKE_CLUSTER_NAME="notacluster"
  run valid_target_pool "$foo_targets" "$foo_current"
  echo "output = ${output}"
  [ "$status" -eq 0 ]
}
