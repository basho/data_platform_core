#! /bin/sh
CACHE_PROXY_PORT=${CACHE_PROXY_PORT:-"22122"}
CACHE_PROXY_PID=${CACHE_PROXY_PID:-"./run/cache_proxy_$CACHE_PROXY_PORT.pid"}
test -e $CACHE_PROXY_PID && pgrep -F $CACHE_PROXY_PID >/dev/null 2>&1
if [ $? != "0" ]; then
    echo "Cache Proxy is not running on the pid from $CACHE_PROXY_PID"
    exit 0
fi
echo "Stopping the Cache Proxy service listening on $CACHE_PROXY_PORT"
kill `cat $CACHE_PROXY_PID`
