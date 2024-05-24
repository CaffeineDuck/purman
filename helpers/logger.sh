#!/bin/bash

REQUIRED_ENV_VARS=(
  LOG_LEVEL
)

for env_var in "${REQUIRED_ENV_VARS[@]}"; do
  if [[ -z "${!env_var}" ]]; then
    echo "Environment variable ${env_var} is not set."
    exit 1
  fi
done

function log_message() {
  local level=$1
  shift
  local message=$@
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

  # Disable exit on error for conditional checks
  set +e

  case $level in
  DEBUG)
    [[ "$LOG_LEVEL" == "DEBUG" ]] && echo "$timestamp [DEBUG] $message"
    ;;
  INFO)
    [[ "$LOG_LEVEL" == "INFO" || "$LOG_LEVEL" == "DEBUG" ]] &&
      echo "$timestamp [INFO] $message"
    ;;
  WARN)
    [[ "$LOG_LEVEL" == "WARN" || "$LOG_LEVEL" == "INFO" ||
      "$LOG_LEVEL" == "DEBUG" ]] && echo "$timestamp [WARN] $message"
    ;;
  ALARM)
    [[ $LOG_LEVEL == "ALARM" || $LOG_LEVEL == "WARN" ||
      $LOG_LEVEL == "INFO" || $LOG_LEVEL == "DEBUG" ]] &&
      echo "$timestamp [ALARM] $message"
    ;;
  ERROR)
    echo "$timestamp [ERROR] $message"
    ;;
  esac

  # Re-enable exit on error for conditional checks
  set -e
}
