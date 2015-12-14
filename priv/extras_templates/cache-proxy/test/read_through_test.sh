#! /usr/bin/env bash
NC_PORT=$1
RIAK_HTTP_PORT=$2
RIAK_HTTP_HOST=${3:-localhost}
RIAK_TEST_BUCKET=${4:-test}

function usage {
    echo "$(cat <<EOF
Usage: $0 «NC_PORT» «RIAK_HTTP_PORT» [RIAK_HTTP_HOST] [RIAK_TEST_BUCKET]

Arguments:
  NC_PORT          - Cache Proxy port, speaking the redis protocol
  RIAK_HTTP_PORT   - Riak HTTP port
  RIAK_HTTP_HOST   - Riak HTTP host name or ip address, default: localhost
  RIAK_TEST_BUCKET - Riak test bucket, default: test

Example:
$0 11211 8091 127.0.0.1 test

Output:
riak get after delete
 nc[test:foo]= , riak[foo]=
cache proxy get after delete
 nc[test:foo]= , riak[foo]=
cache proxy get after put
 nc[test:foo]=bar , riak[foo]=bar
EOF
)"
}

if [[ $NC_PORT == "" || $RIAK_HTTP_PORT == "" || $RIAK_HTTP_HOST == "" || $RIAK_TEST_BUCKET == "" ]]; then
    usage && exit 1
fi

function ensure_redis_cli {
    if [[ $(which redis-cli) == "" ]]; then
        echo "adding local redis to path"
        local DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
        PATH=$PATH:$DIR/../../redis/bin
    fi

    if [[ $(which redis-cli) == "" ]]; then
        echo "unable to locate redis-cli, ensure it is in the PATH"
        exit 1
    fi
}

function ensure_curl {
    if [[ $(which curl) == "" ]]; then
        echo "unable to locate curl, ensure it is in the PATH"
        exit 1
    fi
}

ensure_redis_cli
ensure_curl

declare -a RIAK_VALUES
declare -a NC_VALUES

function set_local_riak_value {
    local KEY=$1
    local VALUE=$2
    RIAK_VALUES[$1]=$2
    RIAK_VALUE=${RIAK_VALUES[$1]}
}
function get_local_riak_value {
    local KEY=$1
    RIAK_VALUE=${RIAK_VALUES[$1]}
}

function set_local_nc_value {
    local KEY=$1
    local VALUE=$2
    NC_VALUES[$1]=$2
    NC_VALUE=$NC_VALUES[$1]
}
function get_local_nc_value {
    local KEY=$1
    NC_VALUE=${NC_VALUES[$1]}
}

function riak_put {
    local RIAK_HTTP_HOST=$1
    local RIAK_HTTP_PORT=$2
    local RIAK_TEST_BUCKET=$3
    local KEY=$4
    local VALUE=$5
    curl -s -X PUT -d "$VALUE" "http://$RIAK_HTTP_HOST:$RIAK_HTTP_PORT/buckets/$RIAK_TEST_BUCKET/keys/$KEY" 1>/dev/null 2>&1
    set_local_riak_value $KEY "$VALUE"
}
function riak_get {
    local RIAK_HTTP_HOST=$1
    local RIAK_HTTP_PORT=$2
    local RIAK_TEST_BUCKET=$3
    local KEY=$4
    local VALUE=$(curl -s "http://$RIAK_HTTP_HOST:$RIAK_HTTP_PORT/buckets/$RIAK_TEST_BUCKET/keys/$KEY")
    if [[ $VALUE == "not found" ]]; then
        VALUE=""
    fi
    set_local_riak_value $KEY "$VALUE"
}
function riak_del {
    local RIAK_HTTP_HOST=$1
    local RIAK_HTTP_PORT=$2
    local RIAK_TEST_BUCKET=$3
    local KEY=$4
    curl -s -X DELETE "http://$RIAK_HTTP_HOST:$RIAK_HTTP_PORT/buckets/$RIAK_TEST_BUCKET/keys/$KEY" 1>/dev/null 2>&1
    set_local_riak_value $KEY ""
}
function nc_put {
    local NC_PORT=$1
    local KEY=$2
    local NC_KEY="test:$KEY"
    local VALUE=$3
    redis-cli -p $NC_PORT set $NC_KEY $VALUE
    set_local_nc_value $KEY "$VALUE"
}
function nc_get {
    local NC_PORT=$1
    local KEY=$2
    local NC_KEY="test:$KEY"
    local VALUE=$(redis-cli -p $NC_PORT get $NC_KEY)
    set_local_nc_value $KEY "$VALUE"
}
function nc_del {
    local NC_PORT=$1
    local KEY=$2
    local NC_KEY="test:$KEY"
    redis-cli -p $NC_PORT del $NC_KEY >/dev/null 2>&1
    set_local_nc_value $KEY ""
}
function debug_val {
    local KEY=$1
    local MSG=${2:-""}
    local NC_KEY="test:$KEY"
    local PROMPT=""
    if [[ $MSG != "" ]]; then
        PROMPT="$MSG"$'\n'
    fi
    get_local_riak_value $KEY
    get_local_nc_value $KEY
    echo "$PROMPT nc[$NC_KEY]=$NC_VALUE , riak[$KEY]=$RIAK_VALUE"
}

riak_del $RIAK_HTTP_HOST $RIAK_HTTP_PORT $RIAK_TEST_BUCKET foo
riak_get $RIAK_HTTP_HOST $RIAK_HTTP_PORT $RIAK_TEST_BUCKET foo
debug_val foo "riak get after delete"

riak_del $RIAK_HTTP_HOST $RIAK_HTTP_PORT $RIAK_TEST_BUCKET foo
nc_del $NC_PORT foo
nc_get $NC_PORT foo
debug_val foo "cache proxy get after delete"

riak_put $RIAK_HTTP_HOST $RIAK_HTTP_PORT $RIAK_TEST_BUCKET foo bar
riak_get $RIAK_HTTP_HOST $RIAK_HTTP_PORT $RIAK_TEST_BUCKET foo
nc_get $NC_PORT foo
debug_val foo "cache proxy get after put"

