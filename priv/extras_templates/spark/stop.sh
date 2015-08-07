if [ "$MASTER_URL" == "" ]; then
    ./sbin/stop-slave.sh
else
    ./sbin/stop-master.sh
fi

