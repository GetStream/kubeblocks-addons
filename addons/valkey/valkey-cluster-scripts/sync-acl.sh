#!/bin/bash
#
# Sync ACL rules from existing shard peers onto a newly-joined pod. Invoked
# by KubeBlocks as the memberJoin lifecycle action.
#
# Env vars in scope (we tolerate either naming so the script works under
# both 1.0.x and 1.1.x KB versions):
#   - KB_JOIN_MEMBER_POD_FQDN     — the pod being joined (injected by KB)
#   - REDIS_POD_FQDN_LIST         — historical upstream name (often unset)
#   - CURRENT_SHARD_POD_FQDN_LIST — name our cmpd actually exposes
#
# If neither list is populated, we have no peers to query and there's
# nothing to sync. Exit 0 in that case rather than failing the join.

service_port=${SERVICE_PORT:-6379}
redis_base_cmd="redis-cli $REDIS_CLI_TLS_CMD -p $service_port -a $REDIS_DEFAULT_PASSWORD"
if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
   redis_base_cmd="redis-cli $REDIS_CLI_TLS_CMD -p $service_port"
fi

# Pick whichever peer list is populated; tolerate either name.
peer_list="${REDIS_POD_FQDN_LIST:-$CURRENT_SHARD_POD_FQDN_LIST}"
if [ -z "$peer_list" ]; then
    echo "No peer FQDN list available (REDIS_POD_FQDN_LIST and CURRENT_SHARD_POD_FQDN_LIST both empty); nothing to sync, exiting 0" >&2
    exit 0
fi

is_ok=false
acl_list=""
# 1. get acl list from other pods
for pod_fqdn in $(echo "$peer_list" | tr ',' '\n'); do
    if [[ "$pod_fqdn" == "$KB_JOIN_MEMBER_POD_FQDN" ]]; then
        continue
    fi
    acl_list=$($redis_base_cmd -h "$pod_fqdn" ACL LIST)
    if [ $? -eq 0 ]; then
        is_ok=true
        break
    fi
done

if [ "$is_ok" = false ]; then
    echo "Failed to get ACL LIST from any peer in: $peer_list" >&2
    exit 1
fi

if [ -z "$acl_list" ]; then
    echo "No ACL rules found in other pods, skip synchronization" >&2
    exit 0
fi

set -e
# 2. apply acl list to current pod
while IFS= read -r user_rule; do
    [[ -z "$user_rule" ]] && continue

    if [[ "$user_rule" =~ ^user[[:space:]]+([^[:space:]]+) ]]; then
        username="${BASH_REMATCH[1]}"
    else
      # skip invalid user rule
      continue
    fi

    if [[ "$username" == "default" ]]; then
        continue
    fi
    rule_part="${user_rule#user $username }"
    $redis_base_cmd -h $KB_JOIN_MEMBER_POD_FQDN ACL SETUSER "$username" $rule_part >&2
done <<< "$acl_list"

$redis_base_cmd -h $KB_JOIN_MEMBER_POD_FQDN ACL save >&2