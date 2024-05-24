#!/usr/bin/env bash

set -e

# Env var required for purman-db
export SCRIPT_DIR="$HOME/.purman/bin"

# Wait time in seconds between each poll
WAIT_TIME=15
# The containers to watch and restart if they crash
CONTAINER_NAMES=$(docker ps --format '{{.Names}}')
# map to store latest processed ids for each container
# for compatibility with bash 3 (default on macOS)
LATEST_PROCESSED_IDS=$(mktemp -d)

# shellcheck source=helpers/db.sh
source $(which purman-db)

function _insert_to_map() {
  local key=$1
  local value=$2
  echo "$value" >"$LATEST_PROCESSED_IDS/$key"
}

function _get_from_map() {
  local key=$1
  cat "$LATEST_PROCESSED_IDS/$key"
}

for container_name in $CONTAINER_NAMES; do
  _insert_to_map "$container_name" 0
done

while true; do
  for container_name in $CONTAINER_NAMES; do
    log_message DEBUG "Checking status_logs of container $container_name"
    latest_status=$(get_latest_container_status_logs_by_name $container_name)
    if [[ -z "$latest_status" ]]; then
      log_message WARN "No status logs found for container $container_name"
      continue
    fi

    IFS='|' read -r id container_name log_type log_fp timestamp <<<"$latest_status"
    if [[ -z "$id" || $log_type != "CRASHED" ]]; then
      log_message DEBUG "Container $container_name is not crashed. Skipping."
      continue
    fi

    latest_processed_id=$(_get_from_map "$container_name")
    if [[ $id -le $latest_processed_id ]]; then
      log_message DEBUG "Latest log for $container_name already processed. Skipping."
      continue
    fi
    _insert_to_map "$container_name" $id

    log_message ALARM "Crashed detected for $container_name. Restarting."
    docker restart $container_name >/dev/null
    log_message INFO "Container $container_name has been restarted."
  done

  sleep $WAIT_TIME
done
