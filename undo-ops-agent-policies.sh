#!/bin/bash
#================================================================
# Revert Google Cloud Ops Agent Policies per the input ZONE.
#================================================================
#
# Version: 0.1
# $Date: 2023/02/22 $ (last updated date)
#
#----------------------------------------------------------------
# Usage
#----------------------------------------------------------------
#
#
# Usage:
#   bash undo-ops-agent-policies.sh ZONE1 ZONE2 ZONE3
#
# It does the following for each ZONE:
# 1. Search for all `goog-ops-agent` prefixed policy assignments for the input ZONE
# 2. For each policy found in step 1:
#    a. Describe then dump the policy into temp file.
#    b. Modify the policy in temp file from installing ops agent to removing ops agent.
#    c. Apply the modified policy to uninstall ops agent.
#    d. Delete the policy.
# 3. Remove `goog-ops-agent-policy` label from impacted VMs.
# TODO(b/273596385): Write a e2e test for this script.

POLICIES_DIR="$(mktemp -d "/tmp/ops-agent-policies.XXXX")"
trap "rm -rf '${POLICIES_DIR}'" EXIT SIGINT SIGTERM
declare -a ZONES=("$@")


undo_policies() {
  local zone=$1
  shift
  local -a policies=("$@")
  for policy in "${policies[@]}"; do
    tmp_yaml_file="${POLICIES_DIR}/${policy}.yaml"
    # 2a. Describe then dump the policy into temp file.
    echo "Describing $policy"
    gcloud compute os-config os-policy-assignments describe "${policy}" --location="${zone}" --format yaml > "${tmp_yaml_file}"
    echo "Updating $policy"
    # 2b. Modify the policy in temp file from installing ops agent to removing ops agent.
    sed -i.original -e 's/desiredState: INSTALLED/desiredState: REMOVED/g' "${tmp_yaml_file}"
    # 2c. Apply the modified policy to uninstall ops agent.
    echo "Applying updated $policy"
    gcloud compute os-config os-policy-assignments update "${policy}" --file="${tmp_yaml_file}" --location="${zone}"
    # 2d. Delete the policy.
    echo "Deleting $policy"
    gcloud compute os-config os-policy-assignments delete "${policy}" --location="${zone}"
  done
  # 3. Remove `goog-ops-agent-policy` label from impacted VMs.
  gcloud compute instances list --format="value(NAME)" --zones="${zone}" --filter="labels=goog-ops-agent-policy" | xargs -I % sh -c 'gcloud compute instances update % --remove-labels=goog-ops-agent-policy --zone="${zone}"'
}

main (){
  for zone in "${ZONES[@]}"; do
    echo "Searching for ops agent policies inside zone: ${zone}..."
    echo "========================================================"
    # 1. Search for all `goog-ops-agent-policy` prefixed policies for the input zone
    local -a policy_names=($(gcloud compute os-config os-policy-assignments list --location "${zone}" --filter="name ~ goog-ops-agent" --format="value(ASSIGNMENT_ID)"))
    undo_policies "${zone}" "${policy_names[@]}"
  done
}

main
