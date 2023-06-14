#!/usr/bin/env bash

# This script restarts containerd for each node (Docker container) reachable through the current cluster connection.

set -o errexit
set -o nounset
set -o pipefail

if [[ "${TRACE-0}" == "1" ]]; then
    set -o xtrace
fi

for node in $(kubectl get nodes -o custom-columns=:.metadata.name); do
  echo "restarting containerd for node $node ..."
  docker exec "$node" systemctl restart containerd; done