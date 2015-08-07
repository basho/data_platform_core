#! /bin/bash

# ensure directory layout
for i in logs work; do
      ! test -d $i && mkdir $i
done

if [ "$MASTER_URL" == "" ]; then
    export HOST=${HOST:-0.0.0.0}
    export LEAD_ELECT_SERVICE_HOSTS=${LEAD_ELECT_SERVICE_HOSTS:-"$HOST:5323"}
    export RIAK_HOSTS=${RIAK_HOSTS:-"$HOST:8087"}
    export SPARK_MASTER_IP=${SPARK_MASTER_IP:-"$HOST"}
    export SPARK_MASTER_PORT=${SPARK_MASTER_PORT:-7077}
    export SPARK_MASTER_WEBUI_PORT=${SPARK_MASTER_WEBUI_PORT:-8080}
    echo "Starting Spark Master"
    exec ./sbin/start-master.sh
else
    export HOST=${HOST:-0.0.0.0}
    export SPARK_WORKER_INSTANCES=${SPARK_WORKER_INSTANCES:-1}
    export SPARK_WORKER_PORT=${SPARK_WORKER_PORT:-7078}
    export SPARK_WORKER_WEBUI_PORT=${SPARK_WORKER_WEBUI_PORT:-8081}
    export RIAK_HOSTS=${RIAK_HOSTS:-"$HOST:8087"}
    echo "Starting Spark Worker"
    exec ./sbin/start-slave.sh $MASTER_URL
fi

