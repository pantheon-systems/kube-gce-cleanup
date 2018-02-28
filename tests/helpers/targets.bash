foo_targets=$(cat <<EOF
gke-foocluster-01-1
gke-foocluster-01-2
EOF
)

foo_current=$(cat <<EOF
gke-foocluster-01-1
gke-foocluster-01-2
gke-foocluster-01-3
EOF
)

bar_current=$(cat <<EOF
gke-barcluster-01-1
gke-barcluster-01-2
gke-barcluster-01-3
gke-barcluster-01-4
EOF
)
