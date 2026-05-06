bind * -::*
tcp-backlog 511
timeout 0
ignore-warnings ARM64-COW-BUG
tcp-keepalive 300
daemonize no
pidfile /var/run/redis_6379.pid
{{ block "logsBlock" . }}
loglevel notice
logfile "/data/running.log"
{{ end }}
databases 16
always-show-logo no
set-proc-title yes
proc-title-template "{title} {listen-addr} {server-mode}"
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
rdb-del-sync-files no
dir /data
replica-serve-stale-data yes
replica-read-only yes
repl-diskless-sync yes
repl-diskless-sync-delay 5
repl-diskless-sync-max-replicas 0
repl-diskless-load disabled
repl-disable-tcp-nodelay no
replica-priority 100
acllog-max-len 128
lazyfree-lazy-eviction no
lazyfree-lazy-expire no
lazyfree-lazy-server-del no
replica-lazy-flush no
lazyfree-lazy-user-del no
lazyfree-lazy-user-flush no
oom-score-adj no
oom-score-adj-values 0 200 800
disable-thp yes

# AOF off: fsync on EBS gp3 caused 30-40ms event-loop stalls (LATENCY DOCTOR
# confirmed). Replicas + EBS-mounted nodes.conf give us cluster-topology
# durability, which is all we need for a cache.
appendonly no
appendfilename "appendonly.aof"
appenddirname "appendonlydir"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
aof-load-truncated yes
aof-use-rdb-preamble yes
aof-timestamp-enabled no

# Disable scheduled BGSAVE forks (default rules tripped every ~90s under our
# load; each fork briefly stalls the event loop).
save ""

slowlog-log-slower-than 10000
slowlog-max-len 128

# Observability: log event-loop stalls > 25ms. Negligible overhead, big
# diagnostic value (without it, LATENCY DOCTOR returns nothing).
latency-monitor-threshold 25

notify-keyspace-events ""
hash-max-listpack-entries 512
hash-max-listpack-value 64
list-max-listpack-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-listpack-entries 128
zset-max-listpack-value 64
hll-sparse-max-bytes 3000
stream-node-max-bytes 4096
stream-node-max-entries 100
activerehashing yes
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60
hz 10
dynamic-hz yes
aof-rewrite-incremental-fsync yes
rdb-save-incremental-fsync yes
jemalloc-bg-thread yes
enable-debug-command yes
aclfile /etc/redis/users.acl

# Single IO thread: at the pod CPU limit, 4 IO threads + main thread caused
# CFS throttling (~8% of periods at 1500m). Our workload is fine
# single-threaded. STARTUP-ONLY (CONFIG SET rejects io-threads).
io-threads 1
io-threads-do-reads yes

# configuration for valkey cluster (Redis-protocol compatible)
cluster-enabled yes
cluster-config-file /data/nodes.conf
cluster-allow-replica-migration no
cluster-node-timeout 5000
cluster-replica-validity-factor 0
cluster-require-full-coverage yes
cluster-allow-reads-when-down no

# Eviction policy: allkeys-lru (cache mode — we want eviction across the
# whole keyspace, not just keys with TTLs).
maxmemory-policy allkeys-lru
# maxmemory: 85% of the pod memory limit, leaving ~15% headroom for
# connection / replication buffers. Persistence is disabled, so no RDB-fork
# memory doubling concern.
{{- $limit_memory := default 0 $.PHY_MEMORY | int }}
{{- if gt $limit_memory 0 }}
maxmemory {{ mulf $limit_memory 0.85 | int }}
{{- end }}

{{- if eq (index $ "TLS_ENABLED") "true"  }}
tls-cert-file {{ $.TLS_MOUNT_PATH }}/tls.crt
tls-key-file {{ $.TLS_MOUNT_PATH }}/tls.key
tls-ca-cert-file {{ $.TLS_MOUNT_PATH }}/ca.crt
tls-auth-clients no
tls-replication yes
tls-cluster yes
port 0
{{- end -}}
