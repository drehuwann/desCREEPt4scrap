#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat << EOF
Usage: $0 [options]

Read HTML from stdin. Examples:
  curl -s http://example.org | $0 [options]
  cat page.html | $0 [options]

Options:
  -h, --help      display this help and exit
  -s, --strict    enable strict parsing of ipv4, robust but might be slow on large streams
  -v, --verbose   enable verbose mode
EOF
}

# Require Bash 4+
[[ ${BASH_VERSINFO[0]} -lt 4 ]] && { echo "Error: Bash 4+ required" >&2; exit 1; }

# Strict IPv4 regex: each octet 0–255
readonly strict_ip_regex='^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$'
# Loose IPv4 regex: matches any 0–999 octets
readonly loose_ip_regex='([0-9]{1,3}\.){3}[0-9]{1,3}'

# Default extraction regex
ip_extract_regex="$loose_ip_regex"

# Flags
verbose=false
strict=false

# Parse optional flags
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    -s|--strict) strict=true ;;
    -v|--verbose) verbose=true ;;
    *) echo "Unknown option: $arg" >&2; usage; exit 1;;
  esac
done

# If strict mode is enabled, use stricter extraction regex
if $strict; then
  ip_extract_regex='((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
fi

# Test HTML
html=$(cat)

# Verbose: HTML preview
if $verbose; then
  echo "=== HTML Preview ===" >&2
  echo "$html" | head -n 20 >&2
  echo "====================" >&2
fi

# Extract JS variables into associative array (direct and XOR assignments)
declare -A jsvars
# Split on ';' to process each assignment individually
while IFS= read -r line; do
  # Remove leading/trailing spaces
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  # Direct assignment: name = number;
  if [[ $line =~ ^([[:alnum:]_]+)[[:space:]]*=[[:space:]]*([0-9]+)$ ]]; then
    jsvars["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
  # XOR assignment: name = number ^ varname;
  elif [[ $line =~ ^([[:alnum:]_]+)[[:space:]]*=[[:space:]]*([0-9]+)\^[[:space:]]*([[:alnum:]_]+)$ ]]; then
    localname="${BASH_REMATCH[1]}"
    lit="${BASH_REMATCH[2]}"
    ref="${BASH_REMATCH[3]}"
    if $verbose; then
	echo "processing $line" >&2
    fi
    if [[ -n "${jsvars[$ref]}" ]]; then
      jsvars["$localname"]=$(( lit ^ jsvars[$ref] ))
    fi
  fi
done < <(echo "$html" | tr ';' '\n')

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
# Extract lines containing IP + document.write(… + XOR …)
#  inside of the <script>…</script> block
ipt[^>]*>document\\.write\\(\".*\"\\+[^)]*\\)</script>" <<<"$html" \
  | while IFS= read -r line; do
    # extract the IP
    ip=$(grep -Eo "$ip_extract_regex" <<<"$line")

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
    printf '%s\t%s\n' "$ip" "$port"
  else
    echo "⚠️ Skipped: invalid IP or port → $ip:$port" >&2
  fi
done
