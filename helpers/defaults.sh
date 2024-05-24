#!/bin/bash

export WAIT_TIME=${WAIT_TIME:-30}

export DIR_PATH=${DIR_PATH:-"$HOME/.purman"}

export LOGS_DIR="$DIR_PATH/logs"
export LOG_LINES=${LOG_LINES:-200}
export LOG_LEVEL=${LOG_LEVEL:-INFO}

export DB_DIR="$DIR_PATH/data"
export DB_PATH="$DB_DIR/docker_stats.db"
