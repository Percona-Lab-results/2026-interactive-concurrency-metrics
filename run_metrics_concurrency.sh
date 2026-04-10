#!/bin/bash

# --- VARIABLES ---
DB_HOST="127.0.0.1"   # REPLACE ME
DB_USER="root"
DB_PASS="password"
DB_DATABASE="sbtest"

POOL_SIZES=(32 12 2)      # The 3 Tiers (GB)

THREADS=(128 256 512)

CONCURRENCY=(8 16 32 64)

# --- DEBUG SETTINGS ---
TABLE_ROWS=5000000
WARMUP_RO_TIME=180
WARMUP_RW_TIME=600
DURATION=900

# TABLE_ROWS=50000
# WARMUP_RO_TIME=10
# WARMUP_RW_TIME=10
# DURATION=30

DBMS_NAME="$1"
DBMS_VER="$2"
IS_READ_ONLY="$3"

CONF_D_DIR="/etc/mysql/conf.d"
sudo cpupower frequency-set -g performance > /dev/null

echo "============= Running benchmarks for ${DBMS_NAME}:${DBMS_VER} ============="

if [[ "$DBMS_NAME" == "percona-server" ]]; then
    IMAGE_PREFIX="percona/"
    CONF_D_DIR="/etc/my.cnf.d"
fi

if [[ "$DBMS_NAME" == "mysql-server" ]]; then
    # Assume the image was built using RPM with the default config location
    CONF_D_DIR="/etc"
fi


if [[ "$DBMS_NAME" == "mariadb" ]]; then
    ADMIN_TOOL="mariadb-admin"
else
    ADMIN_TOOL="mysqladmin"
fi  

IMAGE_NAME="${IMAGE_PREFIX}${DBMS_NAME}:${DBMS_VER}"

CONTAINER_NAME="dbms-benchmark-test"

MYSQL_ROOT_PASSWORD="password"
CONFIG_DIR="$HOME/configs"
CONFIG_NAME="my.cnf"
CONFIG_PATH="${CONFIG_DIR}/${CONFIG_NAME}"


server_wait() {
  # Wait for MySQL to be ready
  echo "Waiting for DB Server to initialize..."
  sleep 5

  # Check that the container exists and is running
  if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" != "true" ]; then
    echo "Fatal error: container '$CONTAINER_NAME' is not running or does not exist. Terminating script."
    exit 1
  fi

  until docker exec "$CONTAINER_NAME" "$ADMIN_TOOL" ping --host=127.0.0.1 -u"root" -p"$DB_PASS" 2>/dev/null; do
    echo "Waiting..."       
    sleep 2
  done
}

stop_container() {
  local CONTAINER=$1
  echo "Stopping container ${CONTAINER}"
  docker container stop "$CONTAINER" 2>/dev/null
  sleep 2
  docker container rm "$CONTAINER" 2>/dev/null
}

run_container() {
  local MOUNT=$1

  if [ -n "$MOUNT" ]; then
    echo "Mounting config from: $CONFIG_PATH"
    MOUNT_ARG="-v ${CONFIG_PATH}:${CONF_D_DIR}/${CONFIG_NAME}:ro"
    # MOUNT_ARG="-v /mnt/nvme/data/:/var/log/mysql:rw ${MOUNT_ARG}"
  fi

  # 1. Define the command as an array
  local cmd=(
    docker run --user mysql --rm -it --name "$CONTAINER_NAME"
    --network host
    $MOUNT_ARG
    -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"
    -e MYSQL_DATABASE="$DB_DATABASE"
    -e MYSQL_ROOT_HOST='%'
    -d "${IMAGE_NAME}"
  )

  # 2. Print the command to the terminal
  echo "Executing: ${cmd[*]}"

  # 3. Run the command
  "${cmd[@]}"
}

# Make sure no containers are running at this stage.
stop_container "$CONTAINER_NAME"

# --- DETECT VERSION & VENDOR ---
echo "Run container to detect the version of the server"

if [[ "$IS_READ_ONLY" == "1" ]]; then
    BENCH_DIR="./benchmark_logs_read_only"
else
    BENCH_DIR="./benchmark_logs_custom"
fi  

echo "Removing old config if exists: $CONFIG_PATH"
sudo rm -rf "$CONFIG_PATH"

# --- THIS NEEDS TO BE DONE IF A VERSION IS "latest" ---
run_container
server_wait 

RAW_VERSION=$(mysql -h $DB_HOST -u $DB_USER -p$DB_PASS -N -e "SELECT VERSION();" 2>/dev/null)
MAJOR_VER=$(echo $RAW_VERSION | cut -d'.' -f1,2)
IS_MARIA=$(echo $RAW_VERSION | grep -i "Maria" | wc -l)

LOG_DIR="${BENCH_DIR}/${DBMS_NAME}/${RAW_VERSION}"
mkdir -p $LOG_DIR

echo "Detected: $RAW_VERSION (Major: $MAJOR_VER, MariaDB: $IS_MARIA)"

check_innodb_buffer() {
    local EXPECTED_GB=$1
    echo ">>> Verifying InnoDB Buffer Pool: ${EXPECTED_GB}GB..."

    # Get the value in bytes and divide by 1024^3 to get GB
    # Note: MySQL returns an integer; we use shell arithmetic to convert
    local ACTUAL_BYTES=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -N -s -e "SELECT @@innodb_buffer_pool_size;" 2>/dev/null)
    local ACTUAL_GB=$(( ACTUAL_BYTES / 1024 / 1024 / 1024 ))

    if [ "$ACTUAL_GB" -ne "$EXPECTED_GB" ]; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "CRITICAL ERROR: Buffer Pool is ${ACTUAL_GB}GB (Expected ${EXPECTED_GB}GB)"
        echo "Aborting entire benchmark script immediately."
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        
        # docker stop "$CONTAINER_NAME" 2>/dev/null
        # Immediate termination of the script
        exit 1
    fi

    echo "Verification successful: Buffer Pool is ${ACTUAL_GB}GB."
}

check_vars_status() {
    local FILE_PREFIX=$1
    echo ">>> Capturing server variables and status..."

    # Capture MySQL server variables into file
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -N -e "SHOW VARIABLES;" > "${FILE_PREFIX}.vars.txt" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "    Variables saved to: ${FILE_PREFIX}.vars.txt"
    else
        echo "    ERROR: Failed to capture variables"
    fi

    # Capture MySQL server status into file
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -N -e "SHOW STATUS;" > "${FILE_PREFIX}.status.txt" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "    Status saved to: ${FILE_PREFIX}.status.txt"
    else
        echo "    ERROR: Failed to capture status"
    fi
}

run_mysql_summary() {
    local FILE_PREFIX=$1
    ./pt-mysql-summary --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASS" > "${FILE_PREFIX}-pt-mysql-summary.txt"
    if [ $? -eq 0 ]; then
        echo "    Server summary saved to: ${FILE_PREFIX}-pt-mysql-summary.txt"
    else
        echo "    ERROR: Failed to server summary with pt-mysql-summary"
    fi
}


# --- CONFIGURATION GENERATOR ---
generate_config() {
    local SIZE=$1
    local CONCUR=$2
    local CFG="/tmp/$CONFIG_NAME"
    rm "$CFG"

    # 1. Start Base Config
    echo "[mysqld]" > "$CFG"
    if [ "$IS_MARIA" -eq 1 ]; then
        echo "log_warnings = 2" >> "$CFG"
    else
        echo "log_error_verbosity = 3" >> "$CFG"
    fi
    echo "log_error = /tmp/Tier${SIZE}G.errlog.txt" >> "$CFG"

    echo "# --- General -------------------------------------------------------------------" >> "$CFG"
    echo "user                            = mysql" >> "$CFG"
    echo "#datadir                         = /var/lib/mysql" >> "$CFG"
    echo "#socket                          = /var/run/mysqld/mysqld.sock" >> "$CFG"
    echo "#pid-file                        = /var/run/mysqld/mysqld.pid" >> "$CFG"
    echo "bind-address                    = 0.0.0.0" >> "$CFG"
    echo "port                            = 3306" >> "$CFG"
    echo "skip-name-resolve               = ON" >> "$CFG"
    echo "performance_schema              = OFF" >> "$CFG"
    echo "" >> "$CFG"

    echo "# --- Connection & Threading ----------------------------------------------------" >> "$CFG"
    echo "max_connections                 = 2000" >> "$CFG"
    echo "max_connect_errors              = 1000000" >> "$CFG"
    echo "max_prepared_stmt_count         = 1000000" >> "$CFG"

    #For MariaDB
    echo "thread_handling                 = pool-of-threads   # MariaDB thread pool" >> "$CFG"
    echo "thread_pool_size                = 80                # match physical core count" >> "$CFG"
    echo "thread_pool_max_threads         = 2000" >> "$CFG"

    echo "thread_stack                    = 512K" >> "$CFG"
    echo "thread_cache_size               = 256" >> "$CFG"
    echo "back_log                        = 4096" >> "$CFG"
    echo "wait_timeout                    = 300" >> "$CFG"
    echo "interactive_timeout             = 300" >> "$CFG"
    echo "connect_timeout                 = 60" >> "$CFG"
    echo "" >> "$CFG"

    echo "# --- InnoDB - Buffer pool Tier -------------------------------------------------" >> "$CFG"
    echo "innodb_buffer_pool_size         = ${SIZE}G" >> "$CFG"

    echo "" >> "$CFG"
    echo "# --- InnoDB – I/O (NVMe can saturate many threads) ----------------------------" >> "$CFG"
    echo "innodb_io_capacity              = 10000" >> "$CFG"
    echo "innodb_io_capacity_max          = 20000" >> "$CFG"
    echo "innodb_read_io_threads          = 16" >> "$CFG"
    echo "innodb_write_io_threads         = 16" >> "$CFG"
    echo "innodb_use_native_aio           = ON" >> "$CFG"
    echo "" >> "$CFG"
    echo "# --- InnoDB instances - one per 5G of memory, but no more than 8 -------------" >> "$CFG"

    echo "# --- InnoDB – Log / Durability -------------------------------------------------" >> "$CFG"
    echo "#innodb_log_file_size is set later with the version specific logic" >> "$CFG"
    echo "innodb_log_buffer_size          = 256M" >> "$CFG"
    echo "innodb_flush_log_at_trx_commit  = 1          # full ACID; use 2 for ~10 % more speed" >> "$CFG"
    echo "innodb_doublewrite              = ON" >> "$CFG"
    echo "" >> "$CFG"

    echo "# --- InnoDB – Concurrency & OLTP Tuning ---------------------------------------" >> "$CFG"
    echo "innodb_thread_concurrency       = ${CONCUR}" >> "$CFG"
    echo "#innodb_adaptive_hash_index      = ON" >> "$CFG"
    echo "#innodb_adaptive_flushing        = ON" >> "$CFG"
    echo "#innodb_adaptive_flushing_lwm    = 10" >> "$CFG"
    echo "#innodb_lru_scan_depth           = 4096" >> "$CFG"
    echo "innodb_stats_on_metadata        = OFF" >> "$CFG"
    echo "innodb_open_files               = 65536" >> "$CFG"
    echo "innodb_lock_wait_timeout        = 50" >> "$CFG"
    echo "innodb_rollback_on_timeout      = ON" >> "$CFG"
    echo "" >> "$CFG"

    echo "# --- Per-Session Buffers (keep modest; many connections × this = RAM) ----------" >> "$CFG"
    echo "sort_buffer_size                = 4M" >> "$CFG"
    echo "join_buffer_size                = 4M" >> "$CFG"
    echo "read_buffer_size                = 2M" >> "$CFG"
    echo "read_rnd_buffer_size            = 4M" >> "$CFG"
    echo "tmp_table_size                  = 256M" >> "$CFG"
    echo "max_heap_table_size             = 256M" >> "$CFG"
    echo "" >> "$CFG"

    echo "# --- Table & File Handles ------------------------------------------------------" >> "$CFG"
    echo "table_open_cache                = 65536" >> "$CFG"
    echo "table_definition_cache          = 65536" >> "$CFG"
    echo "open_files_limit                = 1000000" >> "$CFG"
    echo "table_open_cache_instances      = 64" >> "$CFG"
    echo "" >> "$CFG"

    echo "# --- Binary Log (enable for replication / PITR) --------------------------------" >> "$CFG"
    # In 5.7, server_id must be specified if binary logging is enabled, otherwise the server is not allowed to start.
    echo "server_id                       = 1" >> "$CFG"
    echo "log_bin                         = /var/lib/mysql/mysql-bin" >> "$CFG"
    echo "binlog_format                   = ROW" >> "$CFG"
    echo "binlog_row_image                = MINIMAL" >> "$CFG"
    #echo "expire_logs_days                = 7" >> "$CFG"
    echo "sync_binlog                     = 1" >> "$CFG"
    echo "binlog_cache_size               = 4M" >> "$CFG"
    echo "max_binlog_size                 = 512M" >> "$CFG"
    echo "" >> "$CFG"

    echo "# --- Slow Query Log ------------------------------------------------------------" >> "$CFG"
    echo "slow_query_log                  = ON" >> "$CFG"
    echo "slow_query_log_file             = /var/lib/mysql/slow.log" >> "$CFG"
    echo "long_query_time                 = 1" >> "$CFG"
    echo "log_queries_not_using_indexes   = OFF" >> "$CFG"
    echo "min_examined_row_limit          = 1000" >> "$CFG"
    echo "" >> "$CFG"

    echo "# --- Character Set -------------------------------------------------------------" >> "$CFG"
    echo "character_set_server            = utf8mb4" >> "$CFG"
    echo "collation_server                = utf8mb4_unicode_ci" >> "$CFG"
    echo "" >> "$CFG"

    echo "# --- Misc ----------------------------------------------------------------------" >> "$CFG"
    echo "max_allowed_packet              = 64M" >> "$CFG"
    echo "bulk_insert_buffer_size         = 256M" >> "$CFG"
    echo "myisam_sort_buffer_size         = 128M" >> "$CFG"
    echo "key_buffer_size                 = 64M        # MyISAM only; keep small for OLTP" >> "$CFG"
    echo "" >> "$CFG"

    echo "# --- Version specific settings -------------------------------------------------" >> "$CFG"

    # 3. VERSION SPECIFIC LOGIC
    INSTANCES=$(( SIZE / 5 ))
    [ "$INSTANCES" -lt 1 ] && INSTANCES=1
    [ "$INSTANCES" -gt 8 ] && INSTANCES=8


    if [ "$IS_MARIA" -eq 1 ]; then
        # --- MARIADB ---
        # Query Cache removed in 12.1+
        if [ "${MAJOR_VER%%.*}" -lt 11 ]; then
            echo "query_cache_type = OFF" >> "$CFG"
            echo "query_cache_size = 0" >> "$CFG"
            echo "innodb_flush_method = O_DIRECT" >> "$CFG"
            echo "innodb_buffer_pool_instances    = $INSTANCES" >> "$CFG"
            echo "innodb_log_files_in_group = 2" >> "$CFG"
            echo "innodb_log_file_size = 2G" >> "$CFG"
        else
            echo "innodb_log_file_size = 4G" >> "$CFG"
        fi
        echo "innodb_data_file_buffering=OFF" >> "$CFG"
        echo "innodb_data_file_write_through=OFF" >> "$CFG"
        echo "innodb_log_file_buffering=ON" >> "$CFG"
        echo "innodb_log_file_write_through=OFF" >> "$CFG"
        echo "innodb_snapshot_isolation        = OFF" >> "$CFG"

    elif [[ "$MAJOR_VER" == "5.7" ]]; then
        # --- MYSQL / PERCONA 5.7 ---
        echo "innodb_log_file_size = 2G" >> "$CFG"
        echo "innodb_log_files_in_group = 2" >> "$CFG"
        echo "innodb_flush_method = O_DIRECT" >> "$CFG"
        echo "innodb_buffer_pool_instances    = $INSTANCES" >> "$CFG"

    elif [[ "$MAJOR_VER" == "8.0" ]]; then
        # --- MYSQL / PERCONA 8.0 ---
        # NOTE: query_cache is REMOVED. Including it here prevents startup.
        echo "innodb_log_file_size = 2G" >> "$CFG"
        echo "innodb_log_files_in_group = 2" >> "$CFG"
        echo "innodb_change_buffering = none" >> "$CFG"
        echo "innodb_flush_method = O_DIRECT" >> "$CFG"
        echo "innodb_buffer_pool_instances    = $INSTANCES" >> "$CFG"
    else
        # --- MYSQL 8.4 / 9.x ---
        # Modern redo log handling
        echo "innodb_redo_log_capacity = 4G" >> "$CFG"
        echo "innodb_change_buffering = none" >> "$CFG"
        echo "innodb_flush_method = O_DIRECT" >> "$CFG"
        echo "innodb_buffer_pool_instances    = $INSTANCES" >> "$CFG"
    fi

    # 4. Deploy Config
    # Ensure directory exists and copy
    echo "mkdir -p $CONFIG_DIR"
    mkdir -p "$CONFIG_DIR"
    echo "sudo cp $CFG $CONFIG_DIR"
    sudo cp "$CFG" "$CONFIG_PATH"
    cp "$CFG" "${LOG_DIR}/Tier${SIZE}G.cnf.txt"

    # Optional: Fix permissions to ensure Docker mysql user can read it
    sudo chmod 644 "$CONFIG_PATH"
}

copy_server_logs() {
    local SIZE=$1
    local DEST_DIR="${LOG_DIR}"

    echo "Copying server logs to ${DEST_DIR}..."
    docker cp "${CONTAINER_NAME}:/tmp/Tier${SIZE}G.errlog.txt" "${DEST_DIR}/"
}


# --- TELEMETRY FUNCTIONS ---
start_metrics() {
    local PREFIX=$1
    echo " --- START METRICS ---"
    echo "iostat -dxm 1 > ${PREFIX}.iostat.txt & echo \$! > /tmp/iostat.pid"
    echo "vmstat 1 > ${PREFIX}.vmstat.txt & echo \$! > /tmp/vmstat.pid"
    echo "mpstat -P ALL 1 > ${PREFIX}.mpstat.txt & echo \$! > /tmp/mpstat.pid"
    echo "dstat -t 1 > ${PREFIX}.dstat.txt & echo \$! > /tmp/dstat.pid"

    # Start collection in background
    HLL_OUTPUT="${PREFIX}.idbhist.txt"
    bash "./collect_history_len.sh" "$HLL_OUTPUT" "$DB_USER" "$DB_PASS" "$DB_HOST" &
    COLLECTOR_PID=$!

    echo "Started HLL collector (PID=$COLLECTOR_PID), writing to $HLL_OUTPUT"
    echo "$COLLECTOR_PID" > /tmp/hll_collector.pid

    iostat -dxm 1 > ${PREFIX}.iostat.txt & echo $! > /tmp/iostat.pid
    vmstat 1 > ${PREFIX}.vmstat.txt & echo $! > /tmp/vmstat.pid
    mpstat -P ALL 1 > ${PREFIX}.mpstat.txt & echo $! > /tmp/mpstat.pid
    dstat -t 1 > ${PREFIX}.dstat.txt & echo $! > /tmp/dstat.pid
}

stop_collector() {
    local COLLECTOR_PID=$(cat /tmp/hll_collector.pid 2>/dev/null)

    if kill -0 "$COLLECTOR_PID" 2>/dev/null; then
        echo "Stopping HLL collector (PID=$COLLECTOR_PID)"
        kill "$COLLECTOR_PID"
        wait "$COLLECTOR_PID" 2>/dev/null
    fi
    echo "HLL data written to $HLL_OUTPUT"
}


stop_metrics() {
    kill $(cat /tmp/iostat.pid) $(cat /tmp/vmstat.pid) $(cat /tmp/mpstat.pid) $(cat /tmp/dstat.pid) 2>/dev/null
}

trap 'stop_metrics; stop_collector' EXIT
trap 'stop_metrics; stop_collector; exit 1' INT TERM

init_data() {
  # echo ">>> Resetting databases..."
  # docker exec "$CONTAINER_NAME" mysql -h $DB_HOST -u $DB_USER -p$DB_PASS -N -e "DROP DATABASE IF EXISTS ${DB_DATABASE}; CREATE DATABASE ${DB_DATABASE};"

  echo ">>> Create tables and insert data..."
  sysbench oltp_read_only --mysql-host=$DB_HOST --mysql-user=$DB_USER --mysql-password=$DB_PASS \
    --mysql-db=$DB_DATABASE --tables=20 --table-size=$TABLE_ROWS --threads=64 prepare
}


set_thread_concurrency() {
    local EXPECTED=$1
    echo ">>> Setting innodb_thread_concurrency = ${EXPECTED}..."

    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" \
        -e "SET GLOBAL innodb_thread_concurrency = ${EXPECTED};" 2>/dev/null

    local ACTUAL=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -N -s \
        -e "SELECT @@innodb_thread_concurrency;" 2>/dev/null)

    if [ "$ACTUAL" -ne "$EXPECTED" ]; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "CRITICAL ERROR: innodb_thread_concurrency is ${ACTUAL} (Expected ${EXPECTED})"
        echo "Aborting entire benchmark script immediately."
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        exit 1
    fi

    echo "Verification successful: innodb_thread_concurrency = ${ACTUAL}."
}

# --- EXECUTION LOOP ---
for SIZE in "${POOL_SIZES[@]}"; do
  echo "========================================================="
  echo ">>> TIER: ${SIZE}GB | VER: $RAW_VERSION <<<"
  echo "========================================================="

  # 1. Apply Config & Restart (once per SIZE tier)
  generate_config $SIZE

  stop_container $CONTAINER_NAME

  echo "Starting server with the new config..."
  run_container 1
  server_wait "$CONTAINER_NAME"
  echo "Container restarted with custom config."
  check_innodb_buffer $SIZE
  check_vars_status "${LOG_DIR}/Tier${SIZE}G"
  init_data
  run_mysql_summary "${LOG_DIR}/Tier${SIZE}G"

  # 2. WARMUP (once per SIZE tier)
  echo ">>> Warmup A: Read-Only (${WARMUP_RO_TIME}s)..."
  sysbench oltp_read_only --mysql-host=$DB_HOST --mysql-user=$DB_USER --mysql-password=$DB_PASS \
    --mysql-db=$DB_DATABASE --tables=20 --table-size=$TABLE_ROWS --threads=16 --time=$WARMUP_RO_TIME run

  if [ "$IS_READ_ONLY" == "1" ]; then
    echo "Read-only mode enabled, skipping read-write warmup and benchmarks."
    TEST_TYPE="oltp_read_only"
  else
    echo ">>> Warmup B: Dirty Writes (${WARMUP_RW_TIME}s)..."
    sysbench oltp_read_write --mysql-host=$DB_HOST --mysql-user=$DB_USER --mysql-password=$DB_PASS \
        --mysql-db=$DB_DATABASE --tables=20 --table-size=$TABLE_ROWS --threads=64 --time=$WARMUP_RW_TIME run
    TEST_TYPE="oltp_read_write"
  fi

  # 3. CONCURRENCY & MEASUREMENT (no restart needed)
  for CONCUR in "${CONCURRENCY[@]}"; do
    echo "========================================================="
    echo ">>> TIER: ${SIZE}GB | CONCURRENCY: ${CONCUR} <<<"
    echo "========================================================="

    set_thread_concurrency $CONCUR

    for THREAD in "${THREADS[@]}"; do
        FILE_PREFIX="${LOG_DIR}/Tier${SIZE}G_Concur${CONCUR}_${THREAD}th"
        echo "   >>> Testing ${THREAD} Threads..."

        start_metrics "$FILE_PREFIX"

        sysbench $TEST_TYPE \
          --mysql-host=$DB_HOST \
          --mysql-user=$DB_USER \
          --mysql-password=$DB_PASS \
          --mysql-db=$DB_DATABASE \
          --tables=20 \
          --table-size=$TABLE_ROWS \
          --threads=$THREAD \
          --time=$DURATION \
          --report-interval=1 \
          --rand-type=uniform \
          --mysql-ssl=off \
          run > "${FILE_PREFIX}.sysbench.txt"

      stop_metrics
      stop_collector
      sleep 10
    done
  done

  copy_server_logs $SIZE
  stop_container "$CONTAINER_NAME"
done
echo "============= Finished benchmarks for ${DBMS_NAME}:${DBMS_VER} ============="