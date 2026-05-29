# shellcheck shell=bash
# shellcheck disable=SC2034

# Tightly scoped spec for the Valkey-specific edits to the cluster bootstrap
# helpers. Full coverage of the upstream script behaviour lives in the redis
# addon's spec; here we cover only what the valkey addon adds:
#
#   - build_single_shard_addslots_command (new helper for 1-shard provisioning)
#   - create_redis_cluster branch on primary_count == 1

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "valkey_cluster_common_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Valkey Cluster Common Bash Script Tests"
  Include $common_library_file
  Include ../valkey-cluster-scripts/valkey-cluster-common.sh

  init() {
    # ut_mode=true makes unset_xtrace_when_ut_mode_false / set_xtrace_when_ut_mode_false
    # no-op so xtrace doesn't leak into stderr expectations.
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file
  }
  AfterAll 'cleanup'

  setup_redis_cli_env() {
    REDIS_CLI_TLS_CMD=""
  }
  Before "setup_redis_cli_env"

  Describe "build_single_shard_addslots_command()"
    Context "without password"
      It "uses CLUSTER ADDSLOTSRANGE 0 16383"
        node_endpoint="172.0.0.1:6379"

        When call build_single_shard_addslots_command "$node_endpoint"
        The output should eq "redis-cli  -h 172.0.0.1 -p 6379  cluster addslotsrange 0 16383"
        The stderr should include "initialize single-shard cluster command: redis-cli  -h 172.0.0.1 -p 6379  cluster addslotsrange 0 16383"
      End
    End

    Context "with password"
      setup() {
        export REDIS_DEFAULT_PASSWORD="password"
      }
      Before "setup"

      un_setup() {
        unset REDIS_DEFAULT_PASSWORD
      }
      After "un_setup"

      It "passes auth via -a and masks password in log"
        node_endpoint="172.0.0.1:6379"

        When call build_single_shard_addslots_command "$node_endpoint"
        The output should eq "redis-cli  -h 172.0.0.1 -p 6379 -a password cluster addslotsrange 0 16383"
        The stderr should include "initialize single-shard cluster command: redis-cli  -h 172.0.0.1 -p 6379 -a ******** cluster addslotsrange 0 16383"
      End
    End
  End

  Describe "create_redis_cluster()"
    Context "with a single primary"
      build_single_shard_addslots_command() {
        echo "ADDSLOTS_CMD"
      }
      build_redis_cluster_create_command() {
        echo "MULTI_SHARD_CMD"
      }
      ADDSLOTS_CMD() { return 0; }
      MULTI_SHARD_CMD() { echo "should not be called"; return 1; }

      It "uses the single-shard ADDSLOTS path and skips --cluster create"
        primary_nodes="172.0.0.1:6379 "

        When call create_redis_cluster "$primary_nodes"
        The status should be success
        The stdout should not include "should not be called"
      End
    End

    Context "with multiple primaries"
      build_single_shard_addslots_command() {
        echo "ADDSLOTS_CMD"
      }
      build_redis_cluster_create_command() {
        echo "MULTI_SHARD_CMD"
      }
      ADDSLOTS_CMD() { echo "should not be called"; return 1; }
      MULTI_SHARD_CMD() { return 0; }

      It "uses the upstream --cluster create path"
        primary_nodes="172.0.0.1:6379 172.0.0.2:6379 172.0.0.3:6379 "

        When call create_redis_cluster "$primary_nodes"
        The status should be success
        The stdout should not include "should not be called"
      End
    End
  End
End
