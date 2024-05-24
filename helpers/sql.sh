#!/bin/bash

REQUIRED_ENV_VARS=(
    STATS_TABLE_NAME
    STATUS_LOGS_TABLE_NAME
)

for env_var in "${REQUIRED_ENV_VARS[@]}"; do
    if [[ -z "${!env_var}" ]]; then
        echo "Environment variable ${env_var} is not set."
        exit 1
    fi
done

export CREATE_CONTAINER_STATS_TABLE_SQL=$(cat <<EOF
    CREATE TABLE IF NOT EXISTS $STATS_TABLE_NAME (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        container_name TEXT,
        cpu_perc REAL,
        mem_perc REAL,
        mem_usage REAL,
        mem_capacity REAL,
        net_input REAL,
        net_output REAL,
        block_input REAL,
        block_output REAL,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
    );
EOF)

export CREATE_CONTAINER_STATUS_LOGS_TABLE_SQL=$(cat <<EOF
    CREATE TABLE IF NOT EXISTS $STATUS_LOGS_TABLE_NAME (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        container_name TEXT,
        log_type TEXT, -- CRASHED | NOT_FOUND | HEALTHY
        log_fp TEXT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
    );
EOF)

export SELECT_LATEST_DUMP_ID_SQL="SELECT id from %s ORDER BY id DESC LIMIT 1"

export SELECT_NEXT_DUMP_ID_SQL="SELECT id from %s HAVING id > %d ORDER BY id ASC"

export SELECT_CONTAINER_STATUS_LOGS_BY_ID_SQL=$(cat <<EOF
    SELECT id, container_name, log_type, log_fp, timestamp 
    FROM $STATUS_LOGS_TABLE_NAME
    WHERE id = %d;
EOF)

export SELECT_CONTAINER_STATS_BY_ID_SQL=$(cat <<EOF
    SELECT 
        id,
        container_name,
        cpu_perc,
        mem_perc,
        mem_usage,
        mem_capacity,
        net_input,
        net_output,
        block_input,
        block_output,
        timestamp
    FROM $STATS_TABLE_NAME
    WHERE id = %d;
EOF)


export SELECT_LATEST_LOG_TYPE_FOR_CONTAINER_SQL=$(cat <<EOF
    SELECT log_type
    FROM $STATUS_LOGS_TABLE_NAME
    WHERE container_name = '%s'
    ORDER BY id DESC
    LIMIT 1;
EOF)

export SELECT_LATEST_CONTAINER_STATS_BY_NAME_SQL=$(cat <<EOF
    SELECT 
        id,
        container_name,
        cpu_perc,
        mem_perc,
        mem_usage,
        mem_capacity,
        net_input,
        net_output,
        block_input,
        block_output,
        timestamp
    FROM $STATS_TABLE_NAME
    WHERE container_name = '%s'
    ORDER BY id DESC
    LIMIT 1;
EOF)

export SELECT_LATEST_CONTAINER_STATUS_LOGS_BY_NAME_SQL=$(cat <<EOF
    SELECT id, container_name, log_type, log_fp, timestamp
    FROM $STATUS_LOGS_TABLE_NAME
    WHERE container_name = '%s'
    ORDER BY id DESC
    LIMIT 1;
EOF)

export INSERT_CONTAINER_STATS_SQL=$(cat <<EOF
    INSERT INTO $STATS_TABLE_NAME (
        container_name,
        cpu_perc,
        mem_perc,
        mem_usage,
        mem_capacity,
        net_input,
        net_output,
        block_input,
        block_output
    ) VALUES (
        '%s',
        %f,
        %f,
        %f,
        %f,
        %f,
        %f,
        %f,
        %f
    );
EOF)

export INSERT_CONTAINER_STATUS_LOG_SQL=$(cat <<EOF
    INSERT INTO $STATUS_LOGS_TABLE_NAME (
        container_name,
        log_type,
        log_fp
    ) VALUES (
        '%s',
        '%s',
        '%s'
    );
EOF)
