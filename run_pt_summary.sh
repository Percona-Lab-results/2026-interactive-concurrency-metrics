#!/bin/bash
# parse_pt_summary.sh
# Extracts key fields from a Percona Toolkit pt-summary output file

if [ ! -f ./pt-summary ]; then
  wget http://percona.com/get/pt-summary 
  chmod +x pt-summary
fi

mkdir benchmark_logs

SUMMARY_FULL="benchmark_logs/pt-summary-full.txt"
SUMMARY_BRIEF="benchmark_logs/pt-summary-brief.txt"
./pt-summary > "$SUMMARY_FULL"

if [[ ! -f "$SUMMARY_FULL" ]]; then
  echo "Error: File '$SUMMARY_FULL' not found."
  exit 1
fi

extract() {
  local label="$1"
  local field="$2"
  local value
  value=$(grep -m1 "^\s*${field}\s*|" "$SUMMARY_FULL" | sed 's/.*| *//')
  printf "%-20s %s\n" "${label}:" "${value:-N/A}"
}

echo "========================================" > "$SUMMARY_BRIEF"
echo " Percona pt-summary System Info" >> "$SUMMARY_BRIEF"
echo "========================================" >> "$SUMMARY_BRIEF"
extract "Platform"     "Platform" >> "$SUMMARY_BRIEF"
extract "Release"      "Release" >> "$SUMMARY_BRIEF"
extract "Kernel"       "Kernel" >> "$SUMMARY_BRIEF"
extract "Architecture" "Architecture" >> "$SUMMARY_BRIEF"
extract "Processors"   "Processors" >> "$SUMMARY_BRIEF"
extract "Models"       "Models" >> "$SUMMARY_BRIEF"
extract "Memory Total" "Total" >> "$SUMMARY_BRIEF"
echo "========================================" >> "$SUMMARY_BRIEF"

rm -f pt-summary