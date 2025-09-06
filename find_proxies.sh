.#!/usr/bin/env bash
# Usage: ./script.sh <url> [-s|--strict] [-v|--verbose]

# Require Bash 4+
[[ ${BASH_VERSINFO[0]} -lt 4 ]] && { echo "Error: Bash 4+ required" >&2; exit 1; }

# Strict IPv4 regex: each octet 0–255
strict_ip_regex='^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$'
# Loose IPv4 regex: matches any 0–999 octets
loose_ip_regex='([0-9]{1,3}\.){3}[0-9]{1,3}'

# Default extraction regex
ip_extract_regex="$loose_ip_regex"

# Flags
verbose=false
strict=false

# Parse optional flags
url="$1"
shift
for arg in "$@"; do
  case "$arg" in
    -s|--strict) strict=true ;;
    -v|--verbose) verbose=true ;;
  esac
done

# If strict mode is enabled, use stricter extraction regex
if $strict; then
  ip_extract_regex='((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
fi

# Fetch HTML
html=$(curl -s "$url")

# Verbose: HTML preview
if $verbose; then
  echo "=== HTML Preview ===" >&2
  echo "$html" | head -n 20 >&2
  echo "====================" >&2
fi

# Extract JS variables into associative array
declare -A jsvars
while IFS= read -r line; do
  if [[ $line =~ var[[:space:]]+([[:alnum:]_]+)[[:space:]]*=[[:space:]]*([0-9]+) ]]; then
    jsvars["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
  fi
done < <(echo "$html")

# Verbose: show extracted variables
if $verbose; then
  echo "=== Extracted JavaScript Variables ===" >&2
  for key in "${!jsvars[@]}"; do
    echo "$key = ${jsvars[$key]}" >&2
  done
  echo "======================================" >&2
fi

# Helper: get numeric value from literal or jsvars
get_value() {
  local token="$1"
  if [[ $token =~ ^[0-9]+$ ]]; then
    echo "$token"
  else
    echo "${jsvars[$token]}"
  fi
}

# Extract IP + XOR expressions
echo "$html" | grep -Eo "$ip_extract_regex.*<script[^>]*>document\.write\(\".*\"\+(.*?)\)</script>" | \
while IFS= read -r line; do
  ip=$(echo "$line" | grep -Eo "$ip_extract_regex")

  # Extract all (x^y) pairs without grep -P
  mapfile -t pairs < <(echo "$line" | grep -Eo '\([[:alnum:]]+\^[[:alnum:]]+\)' | tr -d '()')

  port=0
  for pair in "${pairs[@]}"; do
    IFS='^' read -r op1 op2 <<< "$pair"
    val1=$(get_value "$op1")
    val2=$(get_value "$op2")
    if [[ -n $val1 && -n $val2 ]]; then
      port=$(( port + (val1 ^ val2) ))
    fi
  done

  # Validate and output
  if [[ "$ip" =~ $strict_ip_regex ]] && (( port >= 0 && port <= 65535 )); then
    echo -e "$ip\t$port"
  else
    echo "⚠️ Skipped: invalid IP or port → $ip:$port" >&2
  fi
done
