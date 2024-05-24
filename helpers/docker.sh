#!/bin/bash

REQUIRED_ENV_VARS=(
  SCRIPT_DIR
)

for env_var in "${REQUIRED_ENV_VARS[@]}"; do
  if [[ -z "${!env_var}" ]]; then
    echo "Environment variable ${env_var} is not set."
    exit 1
  fi
done

# shellcheck source=helpers/utils.sh
source $SCRIPT_DIR/helpers/utils.sh

function get_all_running_container_names() {
  docker ps --format "{{.Names}}"
}

function get_container_stats() {
  local container_names=("$@")
  docker_stats=$(docker stats --no-stream --format "{{ json . }}" $container_names)
  echo $docker_stats
}

function get_container_status() {
  local container_name=$1

  local running=$(docker inspect --format="{{ .State.Running }}" "$container_name" 2>/dev/null)
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    echo 404 # Container not found
  elif [ "$running" == "true" ]; then
    echo 200 # Container is running
  else
    echo 500 # Container has crashed
  fi
}

function dump_container_logs() {
  local container_name=$1
  local log_fp=$2

  local log_lines=${LOG_LINES:-200}

  docker logs --tail $log_lines $container_name &>$log_fp
}
