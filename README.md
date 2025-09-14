# desCREEPt4scrap
A lightweight parser for decoding obfuscated proxy listings from HTML sources.
It reads HTML from **stdin** and prints `IP<TAB>PORT` lines.

## ⚠️ Disclaimer
This repository is published for **educational purposes only**.

Its contents—including scripts, test files, and documentation—are intended to demonstrate parsing techniques, reverse engineering of obfuscated JavaScript, and general web data analysis.  
No part of this project is meant to promote or facilitate unauthorized access, scraping, or misuse of third-party websites.

> Users are responsible for ensuring their use of this code complies with all applicable laws and the terms of service of any external sites referenced.

## Test Data
A sample HTML file is provided in the [`private4Debug/test.html`](private4Debug/test.html), for testing purposes.  
This file was captured from [spys.one](https://spys.one), a public proxy listing service that embeds proxy IPs and obfuscated ports using JavaScript expressions.

## Requirements
- Bash 4+
- Standard GNU tools: `grep`, `head`, `tr`, `printf`

## Installation
``` bash
git clone https://github.com/drehuwann/desCREEPt4scrap.git
cd desCREEPt4scrap
chmod +x find_proxies.sh
```

## Usage
Read HTML from stdin (pipe or redirect):

# Basic usage
`curl -s https://example.org/page.html | ./find_proxies.sh`

# Strict IPv4 validation
`curl -s https://example.org/page.html | ./find_proxies.sh --strict`

# Verbose mode (HTML preview + extracted JS vars)
`cat page.html | ./find_proxies.sh -v`

# Help
`./find_proxies.sh --help`

## Options
-h, --help — Show help and exit

-s, --strict — Strict IPv4 parsing (each octet 0–255). Must be convenient for robustness, but might be slow against large streams.

-v, --verbose — Verbose mode (HTML preview and extracted JS vars to stderr)

## How it works
Scans HTML for IPv4 addresses.

Looks for `\<script>` blocks containing `document.write("..."+(a^b)+(...))` patterns.

Extracts numeric or variable assignments from JS-like lines (e.g., x = 123; y = 7 ^ x;).

Resolves variables and sums all XOR pairs to produce the port.

## Example output
```text
192.0.2.42  8080
198.51.100.10   3128
203.0.113.5 1080
```
*(Example IPs use documentation ranges from [RFC 5737](https://datatracker.ietf.org/doc/html/rfc5737)).*

## Notes
Input must come from stdin; the script will block if no input is provided.

In verbose mode, previews and diagnostics are sent to stderr; only `IP\<TAB>PORT` lines go to stdout.

## License
This project is licensed under the GNU General Public License v3.0 — see See the [LICENSE](LICENSE) for details.