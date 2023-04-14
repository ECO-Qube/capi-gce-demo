#!/usr/bin/env bash

set -u

delete_bmh() {
  name="${1:-host-0}"
  # We do not care about deprovisioning here since we will anyway delete the VM.
  # So to speed things up, we detach it before deleting.
  kubectl annotate bmh "${name}" baremetalhost.metal3.io/detached=""
  kubectl delete bmh "${name}"
  kubectl -n vbmc exec deploy/vbmc -- vbmc delete "${name}"
  virsh destroy --domain "${name}"
  virsh undefine --domain "${name}" --remove-all-storage
}

delete_bmh "${1}"
