#!/bin/bash

REQUIRED_ENV_VARS=(
  TELEGRAM_BOT_TOKEN
  TELEGRAM_CHANNEL_ID
)

for env_var in "${REQUIRED_ENV_VARS[@]}"; do
  if [[ -z "${!env_var}" ]]; then
    echo "Environment variable ${env_var} is not set."
    exit 1
  fi
done

WAIT_TIME=60
CONTAINER_NAMES=$(docker ps --format '{{.Names}}')
DIR_PATH="tmp/notify_restart_purman"
PIDS=()

function restart_crashed_containers() {
  ./scripts/auto_restart.sh watch_stats
}

function start_all() {
  ./purman.sh dump_status &
  PIDS+=($!)
  ./scripts/auto_restart.sh watch_status &
  PIDS+=($!)
  ./scripts/notify_telegram.sh watch_status &
  PIDS+=($!)
  echo "Started all processes. PIDs: ${PIDS[@]}"
}

function stop_all() {
  for pid in "${PIDS[@]}"; do
    kill $pid 2>/dev/null
    if [[ $? -eq 0 ]]; then
      echo "Stopped process with PID $pid"
    else
      echo "Failed to stop process with PID $pid"
    fi
  done
  PIDS=()
}

function main() {
  start_all
  # Wait for user to terminate the script with Ctrl+C or another method
  trap stop_all EXIT
  while :; do sleep 1; done
}

main
