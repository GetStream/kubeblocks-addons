#!/bin/bash

# This is magic for shellspec ut framework. "test" is a `test [expression]` well known as a shell command.
# Normally test without [expression] returns false. It means that __() { :; }
# function is defined if this script runs directly.
#
# shellspec overrides the test command and returns true *once*. It means that
# __() function defined internally by shellspec is called.
#
# In other words. If not in test mode, __ is just a comment. If test mode, __
# is a interception point.
#
# you should set ut_mode="true" when you want to run the script in shellspec file.
#
# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -e".
  set -ex;
}

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

check_redis_ok() {
  unset_xtrace_when_ut_mode_false
  service_port=${SERVICE_PORT:-6379}
  if ! is_empty "$REDIS_DEFAULT_PASSWORD"; then
    cmd="redis-cli $REDIS_CLI_TLS_CMD -h localhost -p $service_port -a $REDIS_DEFAULT_PASSWORD ping"
  else
    cmd="redis-cli $REDIS_CLI_TLS_CMD -h localhost -p $service_port ping"
  fi
  response=$($cmd)
  status=$?
  set_xtrace_when_ut_mode_false
  if [ $status -eq 124 ]; then
    echo "Timed out" >&2
    return 1
  fi
  if [ "$response" != "PONG" ]; then
    echo "redis ping failed, response: $response" >&2
    return 1
  fi
  echo "Redis is ok"
}

retry_check_redis_ok() {
  if call_func_with_retry 5 3 check_redis_ok; then
    return 0
  else
    echo "Redis is not running." >&2
    return 1
  fi
}

# check_replica_synced gates readiness on replication state, not just PING.
#
# Why: the default PING check returns PONG the moment the server accepts
# connections — which is DURING a replica's full sync, before it holds any
# data. KubeBlocks' Serial rolling update waits on pod-Ready before moving to
# the next pod (and before switchover promotes a replica), so a PING-only
# readiness lets the update advance while a recreated replica is still empty.
# With AOF off that flushes the shard when the role lands on the unsynced pod.
#
# Gate: a master (or a node whose role can't be read) is Ready on PING alone.
# A replica is Ready only when master_link_status:up — its initial sync from
# the primary has completed and it actually holds the dataset. This makes the
# Serial update wait for full sync before switchover, closing the
# readiness-before-sync window.
check_replica_synced() {
  unset_xtrace_when_ut_mode_false
  service_port=${SERVICE_PORT:-6379}
  if ! is_empty "$REDIS_DEFAULT_PASSWORD"; then
    info=$(redis-cli $REDIS_CLI_TLS_CMD -h localhost -p "$service_port" -a "$REDIS_DEFAULT_PASSWORD" info replication 2>/dev/null)
  else
    info=$(redis-cli $REDIS_CLI_TLS_CMD -h localhost -p "$service_port" info replication 2>/dev/null)
  fi
  set_xtrace_when_ut_mode_false
  role=$(echo "$info" | awk -F: '/^role:/{print $2}' | tr -d '[:space:]')
  if [ "$role" != "slave" ]; then
    # master, or role indeterminate — PING already confirmed it serves.
    return 0
  fi
  link=$(echo "$info" | awk -F: '/^master_link_status:/{print $2}' | tr -d '[:space:]')
  if [ "$link" = "up" ]; then
    return 0
  fi
  echo "replica not yet synced (master_link_status=${link:-unknown}); not ready" >&2
  return 1
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library
retry_check_redis_ok || exit 1
check_replica_synced || exit 1
