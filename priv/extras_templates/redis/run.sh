#! /bin/sh
HOST=${HOST:-"0.0.0.0"}
REDIS_PORT=${REDIS_PORT:-6379}

echo "Starting Redis Server"
exec ./bin/redis-server --bind ${HOST} --port ${REDIS_PORT}
