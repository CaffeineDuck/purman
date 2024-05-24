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

# shellcheck source=helpers/defaults.sh
source $SCRIPT_DIR/helpers/defaults.sh
# shellcheck source=helpers/logger.sh
source $SCRIPT_DIR/helpers/logger.sh

check_required_args() {
  local function_name=$1
  shift
  local args=("$@")
  local missing=0

  for arg in "${args[@]}"; do
    if [ -z "${!arg}" ]; then
      log_message ERROR "Required argument $arg is missing for function $function_name"
      missing=1
    fi
  done

  if [ $missing -eq 1 ]; then
    exit 1
  fi
}

function handle_exit() {
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    log_message "ERROR" "Script exited with code $exit_code at line ${BASH_LINENO[0]} due to command: ${BASH_COMMAND}"
  fi
}

function convert_to_bytes() {
  local value=$1
  echo $value | awk '
        /KiB/ {printf "%.0f", $1 * 1024; exit}
        /MiB/ {printf "%.0f", $1 * 1024 * 1024; exit}
        /GiB/ {printf "%.0f", $1 * 1024 * 1024 * 1024; exit}
        /TiB/ {printf "%.0f", $1 * 1024 * 1024 * 1024 * 1024; exit}
        /kB/ {printf "%.0f", $1 * 1000; exit}
        /MB/ {printf "%.0f", $1 * 1000 * 1000; exit}
        /GB/ {printf "%.0f", $1 * 1000 * 1000 * 1000; exit}
        /TB/ {printf "%.0f", $1 * 1000 * 1000 * 1000 * 1000; exit}
        /B/ {printf "%.0f", $1; exit}
        {print "Error: Unrecognized format"; exit 1}
    '
}

function create_dir_if_not_exists() {
  local dir_path=$1

  if [[ ! -d "$dir_path" ]]; then
    log_message DEBUG "Directory $dir_path does not exist. Creating it."
    mkdir -p "$dir_path"
    log_message DEBUG "Directory $dir_path created successfully."
  else
    log_message DEBUG "Directory $dir_path already exists."
  fi
}

function generate_random_string() {
  local length=$1
  echo $(openssl rand -hex $length)
}
