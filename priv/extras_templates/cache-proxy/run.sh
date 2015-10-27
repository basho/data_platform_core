#! /bin/sh
HOST=${HOST:-"0.0.0.0"}
CACHE_PROXY_PORT=${CACHE_PROXY_PORT:-"22122"}
CACHE_PROXY_STATS_PORT=${CACHE_PROXY_STATS_PORT:-"22123"}

CACHE_PROXY_BIN=${CACHE_PROXY_BIN:-"./bin/nutcracker"}
CACHE_PROXY_CONFIG=${CACHE_PROXY_CONFIG:-"./config/cache_proxy_$CACHE_PROXY_PORT.yml"}

REDIS_SERVERS=${REDIS_SERVERS:-"127.0.0.1:6379"}
RIAK_KV_SERVERS=${RIAK_KV_SERVERS:-"127.0.0.1:8087"}
# CSV to array server lists, NOTE: also supports space-delimited string
IFS=","
echo "$REDIS_SERVERS" | while read line
do
    for field in "$line"
    do
        REDIS_SERVERS="$REDIS_SERVERS $field"
    done
done
echo "$RIAK_KV_SERVERS" | while read line
do
    for field in "$line"
    do
        RIAK_KV_SERVERS="RIAK_KV_SERVERS $field"
    done
done
CACHE_TTL=${CACHE_TTL:-"15s"}

CACHE_PROXY_RUN_LOG=${CACHE_PROXY_RUN_LOG:-"./log/cache_proxy_$CACHE_PROXY_PORT.log"}
CACHE_PROXY_ERROR_LOG=${CACHE_PROXY_ERROR_LOG:-"./log/cache_proxy_$CACHE_PROXY_PORT.error.log"}
CACHE_PROXY_PID=${CACHE_PROXY_PID:-"./run/cache_proxy_$CACHE_PROXY_PORT.pid"}

# libprotobuf-c is dynamically linked, expected in default load path, but adding
# local ./lib path for a least privilege requirement
LD_LIBRARY_PATH=$LD_LIBRARY_PATH:./lib
LD_LOAD_PATH=$LD_LOAD_PATH:./lib
DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH:./lib
export LD_LIBRARY_PATH
export LD_LOAD_PATH
export DYLD_LIBRARY_PATH

create_config_content () {
    host=$1
    cache_proxy_port=$2
    cache_ttl=$3

    CONFIG_CONTENT=$(cat <<EOF
bdp_cache_proxy:
  listen: $HOST:$CACHE_PROXY_PORT
  hash: fnv1a_64
  distribution: ketama
  auto_eject_hosts: true
  redis: true
  server_retry_timeout: 2000
  server_failure_limit: 1
  server_ttl: $CACHE_TTL
  servers:
EOF
)
}

append_redis_servers_config_lines () {
    redis_servers=$1

    for redis_server in $redis_servers; do
        config_line=$(cat <<EOF
    - $redis_server:1
EOF
)
        CONFIG_CONTENT="$CONFIG_CONTENT\n$config_line"
    done
}

append_riak_kv_servers_config_lines () {
    riak_kv_servers=$1

    if [ "$riak_kv_servers" = "" ]; then
        return
    fi

    CONFIG_CONTENT="$CONFIG_CONTENT\n$(cat <<EOF
  backend_type: riak
  backend_max_resend: 2
  backends:
EOF
)"
    for riak_kv_server in $riak_kv_servers; do
        config_line=$(cat <<EOF
    - $riak_kv_server:1
EOF
)
        CONFIG_CONTENT="$CONFIG_CONTENT\n$config_line"
    done
}

# ensure directory layout
for i in bin config lib log run; do
  ! test -d $i && mkdir $i
done
! test -e bin/nutcracker && mv nutcracker bin/

create_config_content $HOST $CACHE_PROXY_PORT $CACHE_TTL
append_redis_servers_config_lines "$REDIS_SERVERS"
append_riak_kv_servers_config_lines "$RIAK_KV_SERVERS"

echo "$CONFIG_CONTENT" >$CACHE_PROXY_CONFIG

test -e $CACHE_PROXY_PID && pgrep -F $CACHE_PROXY_PID >/dev/null 2>&1
if [ $? = "0" ]; then
    echo "Cache Proxy service is already running, see $CACHE_PROXY_PID"
    exit 1
fi

echo "Starting Cache Proxy service, listening on $CACHE_PROXY_PORT, stats on $CACHE_PROXY_STATS_PORT"
exec $CACHE_PROXY_BIN -s $CACHE_PROXY_STATS_PORT -c $CACHE_PROXY_CONFIG 1>>$CACHE_PROXY_RUN_LOG 2>>$CACHE_PROXY_ERROR_LOG
echo $! >$CACHE_PROXY_PID
