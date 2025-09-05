#!/bin/bash

# Usage: ./script.sh <url> [-s|--strict] [-v|--verbose]

# Strict IPv4 regex: each octet must be between 0 and 255
strict_ip_regex='^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$'

# Loose IPv4 regex: matches any 0–999 octets (used by default)
loose_ip_regex='(\d{1,3}\.){3}\d{1,3}'

# Default assignment
ip_extract_regex="$loose_ip_regex"

# Flags
verbose=false
strict=false

# Parse optional flags
for arg in "$@"; do
  case "$arg" in
    -v|--verbose) verbose=true ;;
    -s|--strict) strict=true ;;
  esac
done

# If strict mode is enabled, use stricter extraction regex
if $strict; then
  ip_extract_regex='(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
fi

# Fetch the HTML content from the given URL and store it in a variable
html=$(curl -s "$1")

# Optional: preview the first few lines for debugging
if $verbose; then
  echo "=== HTML Preview ===" >&2
  echo "$html" | head -n 20 >&2
  echo "====================" >&2
fi

# jsvars is an associative array that stores JavaScript variable names and their numeric values
declare -A jsvars
while IFS= read -r line; do
  name=$(echo "$line" | grep -Po 'var\s+\K\w+(?=\s*=)')
  value=$(echo "$line" | grep -Po '(?<==\s*)\d+(?=;)')
  if [[ -n "$name" && -n "$value" ]]; then
    jsvars["$name"]=$value
  fi
done < <(echo "$html" | grep -Po 'var\s+\w+\s*=\s*\d+;')

# Optional: print all extracted JavaScript variables
if $verbose; then
  echo "=== Extracted JavaScript Variables ===" >&2
  for key in "${!jsvars[@]}"; do
    echo "$key = ${jsvars[$key]}" >&2
  done
  echo "======================================" >&2
fi

# Extract IP and XOR-based port expressions from the HTML
echo "$html" | grep -Po "$ip_extract_regex.*?<script[^>]*>document\.write\(\".*?\"\+(.*?)\)</script>" | while IFS= read -r line; do
  ip=$(echo "$line" | grep -Po "$ip_extract_regex")

  expr=$(echo "$line" | grep -Po '\(([^)]+)\)' | tr '\n' '+' | sed 's/+$//')

  port=0
  for pair in $(echo "$expr" | tr '+' '\n'); do
    a=$(echo "$pair" | cut -d'^' -f1)
    b=$(echo "$pair" | cut -d'^' -f2)
    if [[ -n "${jsvars[$a]}" && -n "${jsvars[$b]}" ]]; then
      port=$((port + (jsvars[$a] ^ jsvars[$b])))
    fi
  done

  # Validate IP and port before displaying
  if [[ "$ip" =~ $strict_ip_regex ]] && (( port >= 0 && port <= 65535 )); then
    echo -e "$ip\t$port"
  else
    echo "⚠️ Skipped: invalid IP or port → $ip:$port" >&2
  fi
done
