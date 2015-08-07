
#!/usr/bin/env bash

# Comma separated list of nodes that provide leader election service
#LEAD_ELECT_SERVICE_HOSTS="172.31.14.135:10012,172.31.14.136,172.31.14.137:10012"

# Leader election namespace. Should be the same for all masters in the same cluster
LEAD_ELECT_NAMESPACE="spark_leaders"

# Comma separeted list of Riak cluster nodes
#RIAK_HOSTS="172.31.14.135:10017,172.31.14.136:10017,172.31.14.137:10017"

if [[ "$LEAD_ELECT_NAMESPACE" != "" ]]; then
    OPT_LEADELECT_NAMESPACE="-Dspark.deploy.leadelect.namespace=$LEAD_ELECT_NAMESPACE"
fi
if [[ "$LEAD_ELECT_SERVICE_HOSTS" != "" ]]; then
    OPT_LEAD_ELECT_SERVICE_HOSTS="-Dspark.deploy.leadelect.service=$LEAD_ELECT_SERVICE_HOSTS"
fi

if [[ "$RIAK_HOSTS" != "" ]]; then
    OPT_RIAK_HOSTS="-Dspark.riak.connection.host=$RIAK_HOSTS"
fi

# Required to provide leader election for the Spark masters
export SPARK_DAEMON_JAVA_OPTS="-Dspark.deploy.recoveryMode=CUSTOM \
-Dspark.deploy.recoveryMode.factory=org.apache.spark.deploy.master.RiakEnsembleRecoveryModeFactory \
-Dspark.deploy.riak.metadata.map=spark-cluster-map \
-Dspark.deploy.riak.consistent.bucket=spark-bucket \
-Dspark.deploy.leadelect.timeout=10000 \
$OPT_LEADELECT_NAMESPACE \
$OPT_LEAD_ELECT_SERVICE_HOSTS \
$OPT_RIAK_HOSTS"

export SPARK_MASTER_OPTS="-cp $SPARK_HOME/lib/*"

