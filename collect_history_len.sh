#!/bin/bash

# Usage: collect_hll.sh <output_file> <user> <password> <host> <port>

OUTPUT_FILE="$1"
MYSQL_USER="$2"
MYSQL_PASS="$3"
MYSQL_HOST="${4:-127.0.0.1}"

if [ -z "$OUTPUT_FILE" ] || [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASS" ]; then
    echo "Usage: $0 <output_file> <user> <password> [host]"
    exit 1
fi

MYSQL_CMD="mysql -u$MYSQL_USER -p$MYSQL_PASS -h$MYSQL_HOST -Nse"

# Write header
echo "timestamp,history_list_length" > "$OUTPUT_FILE"

while true; do
    HLL=$($MYSQL_CMD "SELECT count FROM information_schema.INNODB_METRICS WHERE name = 'trx_rseg_history_len';" 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$HLL" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'),$HLL" >> "$OUTPUT_FILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S'),ERROR" >> "$OUTPUT_FILE"
    fi

    sleep 1
done