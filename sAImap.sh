#!/bin/bash
# ==========================================================
# sAImap.sh - Multi-tool Subdomain & HTTP Scanner
# v5.0 - Major rewrite with improved reliability, reporting,
#         scope validation, wildcard detection, recursive
#         discovery, CIDR expansion, and HTML/JSON reports.
# ==========================================================

set -uo pipefail

VERSION="5.0"

# --- Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YEL='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Default configuration
THREADS=50
TIMEOUT_TOOL=256
TIMEOUT_CURL=15
OUTPUT_FILE=""
INPUT_FILE=""
USE_DISCOVERY=false
USE_HTTPX=false
BLACKLIST_FILE=""
WORDLIST=""
OUTPUT_DIR=""
RECURSIVE=false
MAX_RECURSIVE_DEPTH=2
RESOLVE_ALL=true
DETECT_WILDCARDS=true
GENERATE_REPORT=false
REPORT_FORMAT="html"
QUIET=false
VERBOSE=false
CONFIG_FILE="${HOME}/.sAImap.conf"
SCOPE_STRICT=true
WEBHOOK_URL=""
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0"

# --- Scan mode: lite / normal / deep
#   lite   = fast tools only, short timeouts (~5-15min)
#   normal = most tools, balanced timeouts (default)
#   deep   = all tools, long timeouts, subfinder -all
SCAN_MODE="normal"

# Tool tiers per mode:
#   lite:   subfinder, findomain, assetfinder, crtsh, dig, host
#   normal: + sublist3r, gau, waybackurls, github-subdomains,
#           archiveurls, otxurls, dnsdumpster, chaos, shodan, censys
#   deep:   + amass, oneforall, subfinder(-all), longer timeouts

# Per-domain timeout per mode (seconds)
TIMEOUT_PER_DOMAIN_LITE=60
TIMEOUT_PER_DOMAIN_NORMAL=120
TIMEOUT_PER_DOMAIN_DEEP=600

# --- HTTP status codes accepted (final code after redirects)
HTTP_ACCEPT="200"

# --- Temporary directory
TEMP_DIR=$(mktemp -d -t sAImap_XXXXXXXX)
trap 'cleanup' EXIT INT TERM

# --- ProjectDiscovery httpx path (detected in check_tools)
HTTPX_BIN=""

# --- Runtime stats
declare -A TOOL_STATS=()
SCAN_START_TIME=0
TOTAL_PASSIVE_SUBS=0
TOTAL_BRUTE_SUBS=0
TOTAL_RESOLVED=0
TOTAL_LIVE=0
WILDCARD_DOMAINS=()

# ==========================================================
# UTILITY FUNCTIONS
# ==========================================================

cleanup() {
    local exit_code=$?
    # Kill any remaining background jobs
    jobs -p 2>/dev/null | xargs -r kill 2>/dev/null || true
    wait 2>/dev/null || true
    rm -rf "$TEMP_DIR"
    exit $exit_code
}

print_usage() {
    cat <<EOF
${CYAN}${BOLD} sAImap v${VERSION} - Subdomain & HTTP Scanner ${NC}

Usage: $0 -f INPUT -o OUTPUT [options]

${BOLD}Required:${NC}
  -f FILE    Input file (domains, one per line)
  -o FILE    Output file (live URLs)

${BOLD}Discovery:${NC}
  -s         Enable subdomain discovery
  -w FILE    Wordlist for DNS bruteforce
  -R         Recursive subdomain discovery (max depth: $MAX_RECURSIVE_DEPTH)
  --lite     Fast scan: only fast tools, 60s/domain timeout (~5-15min)
  --deep     Thorough scan: all tools incl. amass/oneforall, 10min/domain timeout
  --mode M   Set scan mode: lite, normal (default), deep
  --no-resolve    Skip DNS resolution step
  --no-wildcard   Skip wildcard detection

${BOLD}Scan modes:${NC}
  ${GREEN}lite${NC}     subfinder, findomain, assetfinder, crt.sh, dig, host,
             github-subdomains — 60s/domain — quick recon or large scope
  ${YEL}normal${NC}   + sublist3r, gau, waybackurls, github-subdomains,
             archiveurls, otxurls, dnsdumpster, chaos, shodan, censys
             120s/domain — balanced (default)
  ${RED}deep${NC}     + amass, oneforall, subfinder -all
             10min/domain — maximum coverage, very slow

${BOLD}Output:${NC}
  -d DIR     Output directory for per-domain results
  --report   Generate HTML report (saved alongside output)
  --json     Generate JSON report instead of HTML

${BOLD}Tuning:${NC}
  -t NUM     HTTP threads [default: $THREADS]
  -T NUM     Passive tools timeout in seconds [default: $TIMEOUT_TOOL]
  -b FILE    Custom blacklist file
  -x         Use httpx instead of curl for HTTP probing
  --ua STR   Custom User-Agent string
  --accept CODES  Final HTTP status codes to accept [default: 200]
                  Redirects (301/302/307/308) are always followed;
                  only the final response code is checked

${BOLD}Other:${NC}
  -q         Quiet mode (minimal output)
  -v         Verbose mode (debug output)
  --config FILE    Config file [default: ~/.sAImap.conf]
  --webhook URL    Send notification on completion
  -h, --help       Show this message
  --version        Show version

${BOLD}Supported tools:${NC}
  ${CYAN}Passive:${NC}     subfinder, findomain, amass, assetfinder, sublist3r
               gau, waybackurls, github-subdomains, oneforall, chaos
               crtsh (tool or curl fallback), otxurls, archiveurls
               dnsdumpster, shodan, censys
  ${CYAN}DNS:${NC}         dig, host, dnsx, massdns
  ${CYAN}Bruteforce:${NC}  puredns, shuffledns, gobuster, dmut, gotator, alterx
  ${CYAN}Network:${NC}     mapcidr

${BOLD}Config file format (~/.sAImap.conf):${NC}
  THREADS=100
  TIMEOUT_TOOL=300
  TIMEOUT_CURL=15
  WEBHOOK_URL=https://hooks.slack.com/...
  USER_AGENT="custom agent"

${BOLD}Examples:${NC}
  $0 -f domains.txt -o alive.txt -s --lite -x          # Quick recon
  $0 -f domains.txt -o alive.txt -s -x                  # Normal scan
  $0 -f domains.txt -o alive.txt -s --deep --report     # Full enumeration
  $0 -f domains.txt -o alive.txt -s -d ./results -w wordlist.txt --report
EOF
    exit 0
}

log()     { $QUIET && return; echo -e "$1" >&2; }
ok()      { $QUIET && return; echo -e "  ${GREEN}✓${NC} $*" >&2; }
fail()    { echo -e "  ${RED}✗${NC} $*" >&2; }
warn()    { $QUIET && return; echo -e "  ${YEL}!${NC} $*" >&2; }
info()    { $QUIET && return; echo -e "${CYAN}[*]${NC} $*" >&2; }
debug()   { $VERBOSE && echo -e "${DIM}[D]${NC} $*" >&2; }
die()     { echo -e "${RED}[FATAL]${NC} $*" >&2; exit 1; }

tool_exists() { command -v "$1" &>/dev/null; }

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

human_duration() {
    local secs=$1
    if (( secs >= 3600 )); then
        printf "%dh%02dm%02ds" $((secs/3600)) $((secs%3600/60)) $((secs%60))
    elif (( secs >= 60 )); then
        printf "%dm%02ds" $((secs/60)) $((secs%60))
    else
        printf "%ds" "$secs"
    fi
}

# ==========================================================
# SCAN MODE / TOOL TIERS
# ==========================================================
# Tier 1 (fast, <2min): subfinder, findomain, assetfinder, crtsh, dig, host, github-subdomains
# Tier 2 (medium, 2-30min): gau, waybackurls, sublist3r, archiveurls, shodan, censys, otxurls, dnsdumpster, chaos
# Tier 3 (slow, 30min+): amass, oneforall, subfinder -all
#
# lite   = tier 1 only         (fast recon, ~5-10min)
# normal = tier 1 + tier 2     (balanced, ~30-60min)
# deep   = tier 1 + 2 + 3     (exhaustive, hours)

# Returns the tier of a given tool (1, 2, or 3)
tool_tier() {
    case "$1" in
        subfinder|findomain|assetfinder|crtsh|crtsh_curl|dig|host|github|github-subdomains)
            echo 1 ;;
        gau|waybackurls|sublist3r|archiveurls|shodan|censys|otxurls|dnsdumpster|chaos)
            echo 2 ;;
        amass|oneforall)
            echo 3 ;;
        *)
            echo 2 ;;  # default to tier 2
    esac
}

# Check if a tool should run in the current scan mode
should_run() {
    local tool_name="$1"
    local tier
    tier=$(tool_tier "$tool_name")
    
    case "$SCAN_MODE" in
        lite)   [[ $tier -le 1 ]] ;;
        normal) [[ $tier -le 2 ]] ;;
        deep)   return 0 ;;        # run everything
        *)      [[ $tier -le 2 ]] ;;
    esac
}

# Get the per-domain timeout for the current mode
get_tool_timeout() {
    case "$SCAN_MODE" in
        lite)   echo "$TIMEOUT_PER_DOMAIN_LITE" ;;
        normal) echo "$TIMEOUT_PER_DOMAIN_NORMAL" ;;
        deep)   echo "$TIMEOUT_PER_DOMAIN_DEEP" ;;
        *)      echo "$TIMEOUT_PER_DOMAIN_NORMAL" ;;
    esac
}

apply_scan_mode() {
    local timeout_per_domain
    timeout_per_domain=$(get_tool_timeout)
    
    case "$SCAN_MODE" in
        lite)
            info "Scan mode: ${GREEN}LITE${NC} (tier 1 tools only, ${timeout_per_domain}s/domain)"
            # Shorten global timeout for fast scanning
            [[ "$TIMEOUT_TOOL" -eq 256 ]] && TIMEOUT_TOOL=120
            ;;
        normal)
            info "Scan mode: ${YEL}NORMAL${NC} (tier 1+2, ${timeout_per_domain}s/domain)"
            ;;
        deep)
            info "Scan mode: ${RED}DEEP${NC} (all tools, ${timeout_per_domain}s/domain)"
            # Enable recursive by default in deep mode
            RECURSIVE=true
            [[ "$TIMEOUT_TOOL" -eq 256 ]] && TIMEOUT_TOOL=600
            ;;
    esac
}

banner() {
    $QUIET && return
    log ""
    log "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    log "${CYAN}║${NC}          ${YEL}${BOLD} sAImap v${VERSION}${NC} ${DIM}- Subdomain Scanner${NC}                 ${CYAN}║${NC}"
    log "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    log ""
}

section() {
    log ""
    log "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    log "${CYAN}║${NC}  ${YEL}${BOLD}$1${NC}"
    log "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    log ""
}

# Count lines safely (empty file = 0)
count_lines() {
    [[ -s "$1" ]] && wc -l < "$1" | tr -d ' ' || echo 0
}

# ==========================================================
# CONFIG FILE
# ==========================================================

load_config() {
    [[ ! -f "$CONFIG_FILE" ]] && return 0
    
    debug "Loading config from $CONFIG_FILE"
    
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        key=$(echo "$key" | tr -d '[:space:]')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"//;s/"$//' | sed "s/^'//;s/'$//")
        
        case "$key" in
            THREADS)        THREADS="$value" ;;
            TIMEOUT_TOOL)   TIMEOUT_TOOL="$value" ;;
            TIMEOUT_CURL)   TIMEOUT_CURL="$value" ;;
            USER_AGENT)     USER_AGENT="$value" ;;
            WEBHOOK_URL)    WEBHOOK_URL="$value" ;;
            HTTP_ACCEPT)    HTTP_ACCEPT="$value" ;;
            BLACKLIST_FILE) [[ -z "$BLACKLIST_FILE" ]] && BLACKLIST_FILE="$value" ;;
        esac
    done < "$CONFIG_FILE"
}

# ==========================================================
# TOOLS VERIFICATION
# ==========================================================

check_tools() {
    section "TOOLS VERIFICATION"
    
    local tools_discovery=(subfinder findomain amass assetfinder sublist3r gau waybackurls github-subdomains crtsh otxurls archiveurls dnsdumpster)
    local tools_dns=(dig host dnsx massdns)
    local tools_brute=(puredns shuffledns gobuster dmut gotator alterx)
    local tools_http=(httpx curl)
    local tools_cidr=(mapcidr)
    
    local available_discovery=()
    local available_dns=()
    local available_brute=()
    local available_http=()
    
    # --- Discovery tools
    log "  ${CYAN}[Passive Discovery]${NC}"
    for tool in "${tools_discovery[@]}"; do
        if tool_exists "$tool"; then
            log "    ${GREEN}✓${NC} $tool"
            available_discovery+=("$tool")
        elif [[ -f "$HOME/.local/bin/$tool" ]]; then
            log "    ${GREEN}✓${NC} $tool ${DIM}(~/.local/bin)${NC}"
            available_discovery+=("$tool")
        else
            log "    ${RED}✗${NC} $tool ${DIM}(not installed)${NC}"
        fi
    done
    
    # CRT.SH curl fallback
    if ! tool_exists crtsh && tool_exists curl; then
        log "    ${YEL}○${NC} crtsh ${CYAN}(curl fallback available)${NC}"
        available_discovery+=("crtsh_curl")
    fi
    
    # OneForAll (special case)
    local ofa_found=false
    if tool_exists oneforall; then
        log "    ${GREEN}✓${NC} oneforall"; ofa_found=true
    elif [[ -f "$HOME/OneForAll/oneforall.py" ]]; then
        log "    ${GREEN}✓${NC} oneforall ${DIM}(~/OneForAll/)${NC}"; ofa_found=true
    elif [[ -f "/opt/OneForAll/oneforall.py" ]]; then
        log "    ${GREEN}✓${NC} oneforall ${DIM}(/opt/OneForAll/)${NC}"; ofa_found=true
    else
        log "    ${RED}✗${NC} oneforall ${DIM}(not installed)${NC}"
    fi
    $ofa_found && available_discovery+=("oneforall")
    
    # Chaos
    if tool_exists chaos; then
        if [[ -n "${PDCP_API_KEY:-}" ]]; then
            log "    ${GREEN}✓${NC} chaos ${CYAN}(API key OK)${NC}"
            available_discovery+=("chaos")
        else
            log "    ${YEL}○${NC} chaos ${YEL}(PDCP_API_KEY missing)${NC}"
        fi
    else
        log "    ${RED}✗${NC} chaos ${DIM}(not installed)${NC}"
    fi
    log ""
    
    # --- Intelligence
    log "  ${CYAN}[Intelligence]${NC}"
    if tool_exists shodan; then
        if shodan info >/dev/null 2>&1; then
            log "    ${GREEN}✓${NC} shodan ${CYAN}(API key OK)${NC}"
            available_discovery+=("shodan_intel")
        else
            log "    ${YEL}○${NC} shodan ${YEL}(run: shodan init <API_KEY>)${NC}"
        fi
    else
        log "    ${RED}✗${NC} shodan ${DIM}(not installed)${NC}"
    fi
    if tool_exists censys; then
        if censys account 2>/dev/null | grep -qi "login\|email" 2>/dev/null; then
            log "    ${GREEN}✓${NC} censys ${CYAN}(API configured)${NC}"
            available_discovery+=("censys_intel")
        elif [[ -n "${CENSYS_API_ID:-}" && -n "${CENSYS_API_SECRET:-}" ]]; then
            log "    ${GREEN}✓${NC} censys ${CYAN}(env vars set)${NC}"
            available_discovery+=("censys_intel")
        else
            log "    ${YEL}○${NC} censys ${YEL}(set CENSYS_API_ID & CENSYS_API_SECRET)${NC}"
        fi
    else
        log "    ${RED}✗${NC} censys ${DIM}(not installed)${NC}"
    fi
    log ""
    
    # --- DNS tools
    log "  ${CYAN}[DNS]${NC}"
    for tool in "${tools_dns[@]}"; do
        if tool_exists "$tool"; then
            log "    ${GREEN}✓${NC} $tool"
            available_dns+=("$tool")
        else
            log "    ${RED}✗${NC} $tool ${DIM}(not installed)${NC}"
        fi
    done
    log ""
    
    # --- Bruteforce/permutation tools
    log "  ${CYAN}[Bruteforce/Permutation]${NC}"
    for tool in "${tools_brute[@]}"; do
        if tool_exists "$tool"; then
            log "    ${GREEN}✓${NC} $tool"
            available_brute+=("$tool")
        else
            log "    ${RED}✗${NC} $tool ${DIM}(not installed)${NC}"
        fi
    done
    log ""
    
    # --- CIDR tools
    log "  ${CYAN}[Network/CIDR]${NC}"
    for tool in "${tools_cidr[@]}"; do
        if tool_exists "$tool"; then
            log "    ${GREEN}✓${NC} $tool"
        else
            log "    ${RED}✗${NC} $tool ${DIM}(not installed)${NC}"
        fi
    done
    log ""
    
    # --- HTTP tools (detect ProjectDiscovery httpx)
    log "  ${CYAN}[HTTP Scan]${NC}"
    HTTPX_BIN=""
    local httpx_ok=false
    
    for path in "$HOME/go/bin/httpx" "/usr/local/go/bin/httpx" "/usr/local/bin/httpx" "/usr/bin/httpx" "$(which httpx 2>/dev/null)"; do
        [[ -z "$path" || ! -x "$path" ]] && continue
        if "$path" -version 2>&1 | grep -qi "projectdiscovery\|Current Version"; then
            HTTPX_BIN="$path"
            httpx_ok=true
            break
        fi
    done
    
    if $httpx_ok; then
        local httpx_ver=$("$HTTPX_BIN" -version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log "    ${GREEN}✓${NC} httpx ${CYAN}(PD v${httpx_ver}: $HTTPX_BIN)${NC}"
        available_http+=("httpx")
    elif tool_exists httpx; then
        log "    ${YEL}○${NC} httpx ${YEL}(Python version - ignored)${NC}"
        log "      ${CYAN}→ go install github.com/projectdiscovery/httpx/cmd/httpx@latest${NC}"
    else
        log "    ${RED}✗${NC} httpx ${DIM}(not installed)${NC}"
    fi
    
    if tool_exists curl; then
        log "    ${GREEN}✓${NC} curl"
        available_http+=("curl")
    else
        log "    ${RED}✗${NC} curl ${DIM}(not installed)${NC}"
    fi
    log ""
    
    # --- Summary
    local td=${#available_discovery[@]}
    local tn=${#available_dns[@]}
    local tb=${#available_brute[@]}
    local th=${#available_http[@]}
    
    log "  ${CYAN}[Summary]${NC}"
    log "    Discovery:  ${GREEN}$td${NC} tools"
    log "    DNS:        ${GREEN}$tn${NC} tools"
    log "    Bruteforce: ${GREEN}$tb${NC} tools"
    log "    HTTP:       ${GREEN}$th${NC} tools"
    log ""
    
    # --- Critical checks
    [[ $th -eq 0 ]] && die "No HTTP tool available (curl or httpx required)"
    
    if $USE_DISCOVERY && [[ $td -eq 0 ]]; then
        die "Option -s enabled but no discovery tool available"
    fi
    
    [[ -n "$WORDLIST" ]] && [[ $tb -eq 0 ]] && warn "Wordlist specified but no bruteforce tool available"
    
    if $USE_HTTPX && [[ -z "$HTTPX_BIN" ]]; then
        warn "Option -x: httpx (ProjectDiscovery) not found, falling back to curl"
        USE_HTTPX=false
    fi
}

# ==========================================================
# ARGUMENT PARSING
# ==========================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f) INPUT_FILE="$2"; shift 2 ;;
            -o) OUTPUT_FILE="$2"; shift 2 ;;
            -d) OUTPUT_DIR="$2"; shift 2 ;;
            -s) USE_DISCOVERY=true; shift ;;
            -w) WORDLIST="$2"; shift 2 ;;
            -t) THREADS="$2"; shift 2 ;;
            -T) TIMEOUT_TOOL="$2"; shift 2 ;;
            -b) BLACKLIST_FILE="$2"; shift 2 ;;
            -x) USE_HTTPX=true; shift ;;
            -R) RECURSIVE=true; shift ;;
            -q) QUIET=true; shift ;;
            -v) VERBOSE=true; shift ;;
            --no-resolve)  RESOLVE_ALL=false; shift ;;
            --no-wildcard) DETECT_WILDCARDS=false; shift ;;
            --lite)    SCAN_MODE="lite"; shift ;;
            --deep)    SCAN_MODE="deep"; shift ;;
            --mode)    SCAN_MODE="$2"; shift 2 ;;
            --report)  GENERATE_REPORT=true; REPORT_FORMAT="html"; shift ;;
            --json)    GENERATE_REPORT=true; REPORT_FORMAT="json"; shift ;;
            --config)  CONFIG_FILE="$2"; shift 2 ;;
            --webhook) WEBHOOK_URL="$2"; shift 2 ;;
            --ua)      USER_AGENT="$2"; shift 2 ;;
            --accept)  HTTP_ACCEPT="$2"; shift 2 ;;
            --version) echo "sAImap v${VERSION}"; exit 0 ;;
            -h|--help) print_usage ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    
    [[ -z "${INPUT_FILE:-}" || -z "${OUTPUT_FILE:-}" ]] && print_usage
    [[ ! -f "$INPUT_FILE" ]] && die "File not found: $INPUT_FILE"
    [[ ! -s "$INPUT_FILE" ]] && die "Empty file: $INPUT_FILE"
    
    # Validate numeric args
    [[ ! "$THREADS" =~ ^[0-9]+$ ]] && die "Invalid threads value: $THREADS"
    [[ ! "$TIMEOUT_TOOL" =~ ^[0-9]+$ ]] && die "Invalid timeout value: $TIMEOUT_TOOL"
    
    # Validate scan mode
    [[ ! "$SCAN_MODE" =~ ^(lite|normal|deep)$ ]] && die "Invalid scan mode: $SCAN_MODE (use: lite, normal, deep)"
    
    # Validate wordlist if specified
    [[ -n "$WORDLIST" && ! -f "$WORDLIST" ]] && die "Wordlist not found: $WORDLIST"
}

# ==========================================================
# BLACKLIST
# ==========================================================

setup_blacklist() {
    if [[ -z "$BLACKLIST_FILE" ]]; then
        BLACKLIST_FILE="$TEMP_DIR/blacklist.txt"
        cat > "$BLACKLIST_FILE" << 'BLACKLIST'
# ===== Microsoft =====
login.microsoftonline.com
login.windows.net
login.live.com
login.microsoft.com
account.live.com
account.microsoft.com
accounts.accesscontrol.windows.net
*.microsoftonline.com
*.microsoftonline-p.com
*.msauth.net
*.msftauth.net
*.msidentity.com
*.sharepoint.com
*.onmicrosoft.com
outlook.office365.com
outlook.office.com
*.office.com
portal.azure.com
*.azurewebsites.net
*.azure-api.net
*.azureedge.net
*.trafficmanager.net
*.vo.msecnd.net
*.windows.net

# ===== Google =====
accounts.google.com
accounts.youtube.com
account.google.com
myaccount.google.com
*.google.com
*.googleapis.com
*.gstatic.com
*.googlevideo.com
*.googleusercontent.com
*.google-analytics.com
*.googleadservices.com
*.googletagmanager.com
*.googlesyndication.com
*.doubleclick.net
*.youtube.com
*.ytimg.com
*.withgoogle.com
*.firebaseapp.com
*.appspot.com

# ===== AWS =====
signin.aws.amazon.com
console.aws.amazon.com
*.amazonaws.com
*.elasticbeanstalk.com
*.elb.amazonaws.com
*.s3.amazonaws.com
*.cloudfront.net
*.awsglobalaccelerator.com

# ===== SSO / Auth providers =====
*.okta.com
*.oktapreview.com
*.onelogin.com
*.auth0.com
*.duosecurity.com
*.ping-eng.com
*.pingone.com
*.forgerock.com
*.cyberark.com
login.salesforce.com
*.my.salesforce.com

# ===== CDN / Static =====
*.akamaiedge.net
*.akamaihd.net
*.akamaitechnologies.com
*.akamai.net
*.edgekey.net
*.edgesuite.net
*.fastly.net
*.fastlylb.net
*.cloudflare.com
*.cloudflare-dns.com
*.cdn.cloudflare.net
*.cdn77.org
*.stackpathdns.com
*.stackpathcdn.com
*.incapdns.net
*.impervadns.net
*.sucuri.net
*.kxcdn.com
*.netlify.app
*.netlify.com
*.vercel.app
*.herokuapp.com
*.pantheonsite.io
*.wpengine.com
*.b-cdn.net
*.azioncdn.net

# ===== Email gateways =====
*.mimecast.com
*.proofpoint.com
*.pphosted.com
*.mailgun.org
*.sendgrid.net
*.sparkpostmail.com
*.mandrillapp.com
*.protection.outlook.com
*.ppe-hosted.com

# ===== Parking / Default =====
*.sedoparking.com
*.parkingcrew.net
*.bodis.com
*.above.com
*.hugedomains.com
*.undeveloped.com
*.dan.com
*.afternic.com

# ===== Hosting panels =====
*.cpanel.net
*.secureclient.com
*.hostgator.com
*.bluehost.com
*.godaddy.com
*.secureserver.net

# ===== Misc infra =====
*.zendesk.com
*.freshdesk.com
*.statuspage.io
*.atlassian.net
*.github.io
*.gitlab.io
*.readthedocs.io
BLACKLIST
    elif [[ ! -f "$BLACKLIST_FILE" ]]; then
        die "Blacklist not found: $BLACKLIST_FILE"
    fi
    
    BLACKLIST_PATTERN=$(grep -v '^#' "$BLACKLIST_FILE" | grep -v '^\s*$' | \
        sed 's/\./\\./g' | sed 's/\*/.*/g' | tr '\n' '|' | sed 's/|$//')
    
    local count
    count=$(grep -cve '^\s*$' "$BLACKLIST_FILE" 2>/dev/null | grep -cve '^#' 2>/dev/null || echo 0)
    count=$(grep -v '^#' "$BLACKLIST_FILE" | grep -cve '^\s*$' 2>/dev/null || echo 0)
    info "Blacklist: $count entries"
}

is_blacklisted() {
    local domain="${1#http*://}"
    domain="${domain%%/*}"
    domain="${domain%%:*}"
    [[ -n "$BLACKLIST_PATTERN" ]] && echo "$domain" | grep -qiE "$BLACKLIST_PATTERN"
}

# ==========================================================
# INPUT PREPARATION
# ==========================================================

prepare_input() {
    local clean="$TEMP_DIR/input_clean.txt"
    
    tr -d '\r' < "$INPUT_FILE" | \
        tr '[:upper:]' '[:lower:]' | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
        sed 's|^https\?://||' | \
        sed 's|/.*||' | \
        sed 's|:.*||' | \
        grep -E '^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$' | \
        sort -u > "$clean"
    
    [[ ! -s "$clean" ]] && die "No valid domain after cleanup"
    
    local n
    n=$(count_lines "$clean")
    info "$n domain(s) loaded"
    INPUT_FILE="$clean"
    
    # Save parent domains for scope validation
    cp "$clean" "$TEMP_DIR/parent_domains.txt"
}

# ==========================================================
# SCOPE VALIDATION
# ==========================================================

filter_in_scope() {
    local input="$1"
    local output="$2"
    local parents="$TEMP_DIR/parent_domains.txt"
    
    if ! $SCOPE_STRICT; then
        cp "$input" "$output"
        return 0
    fi
    
    > "$output"
    
    while IFS= read -r sub; do
        sub=$(echo "$sub" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$sub" ]] && continue
        
        # Strip wildcard prefix
        sub="${sub#\*.}"
        
        # Check if subdomain belongs to any parent domain
        while IFS= read -r parent; do
            if [[ "$sub" == "$parent" || "$sub" == *."$parent" ]]; then
                echo "$sub" >> "$output"
                break
            fi
        done < "$parents"
    done < "$input"
    
    sort -u "$output" -o "$output"
}

# ==========================================================
# WILDCARD DETECTION
# ==========================================================

detect_wildcards() {
    local subs_file="$1"
    
    ! $DETECT_WILDCARDS && return 0
    [[ ! -s "$subs_file" ]] && return 0
    
    info "Detecting wildcard DNS..."
    
    local parents="$TEMP_DIR/parent_domains.txt"
    WILDCARD_DOMAINS=()
    local wc_file="$TEMP_DIR/wildcard_domains.txt"
    > "$wc_file"
    
    while IFS= read -r parent; do
        # Generate random subdomain
        local random_sub
        random_sub="sAImap-wc-$(head -c 12 /dev/urandom | md5sum | head -c 16)"
        local test_domain="${random_sub}.${parent}"
        
        local resolved=""
        if tool_exists dig; then
            resolved=$(dig +short "$test_domain" A 2>/dev/null | head -1)
        elif tool_exists host; then
            resolved=$(host "$test_domain" 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}')
        fi
        
        if [[ -n "$resolved" && "$resolved" != *"NXDOMAIN"* && "$resolved" != *"SERVFAIL"* ]]; then
            WILDCARD_DOMAINS+=("$parent")
            echo "$parent" >> "$wc_file"
            warn "Wildcard detected: *.${parent} -> ${resolved}"
        fi
    done < "$parents"
    
    if [[ ${#WILDCARD_DOMAINS[@]} -gt 0 ]]; then
        warn "${#WILDCARD_DOMAINS[@]} wildcard domain(s) detected"
        
        # For wildcard domains, we need to filter more carefully
        # Remove subdomains that resolve to the wildcard IP
        local filtered="$TEMP_DIR/subs_nowildcard.txt"
        cp "$subs_file" "$filtered"
        
        for wc_domain in "${WILDCARD_DOMAINS[@]}"; do
            local wc_ip
            wc_ip=$(dig +short "sAImap-wc-$(head -c 8 /dev/urandom | md5sum | head -c 10).${wc_domain}" A 2>/dev/null | head -1)
            [[ -z "$wc_ip" ]] && continue
            
            debug "Filtering wildcard for $wc_domain (IP: $wc_ip)"
            
            local keep="$TEMP_DIR/wc_keep.txt"
            > "$keep"
            
            while IFS= read -r sub; do
                if [[ "$sub" == *".$wc_domain" || "$sub" == "$wc_domain" ]]; then
                    local sub_ip
                    sub_ip=$(dig +short "$sub" A 2>/dev/null | head -1)
                    if [[ "$sub_ip" != "$wc_ip" ]]; then
                        echo "$sub" >> "$keep"
                    fi
                else
                    echo "$sub" >> "$keep"
                fi
            done < "$filtered"
            
            mv "$keep" "$filtered"
        done
        
        local before after
        before=$(count_lines "$subs_file")
        after=$(count_lines "$filtered")
        local removed=$((before - after))
        
        if [[ $removed -gt 0 ]]; then
            info "Removed $removed wildcard entries"
            mv "$filtered" "$subs_file"
        fi
    else
        ok "No wildcard domains detected"
    fi
}

# ==========================================================
# SUBDOMAIN DISCOVERY
# ==========================================================

run_tool() {
    local name="$1"
    local cmd="$2"
    local out="$3"
    local start
    start=$(date +%s)
    
    debug "Running: $name"
    
    eval "$cmd" > "$out" 2>"$out.err"
    local ret=$?
    local elapsed=$(( $(date +%s) - start ))
    local count=0
    [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
    
    local status="ok"
    local errmsg=""
    
    if [[ $ret -eq 124 ]]; then
        status="timeout"
        errmsg="timeout after ${TIMEOUT_TOOL}s"
    elif [[ $ret -ne 0 && $count -eq 0 ]]; then
        status="fail"
        errmsg=$(head -1 "$out.err" 2>/dev/null | tr -d '\n' | cut -c1-80)
    fi
    
    echo "${status}:${count}:${elapsed}:${errmsg}"
}

launch_passive_tool() {
    local name="$1"
    local cmd="$2"
    local results_dir="$3"
    local stats_dir="$4"
    local pids_file="$5"
    
    (
        local out="$results_dir/${name}.txt"
        local result
        result=$(run_tool "$name" "$cmd" "$out")
        echo "$result" > "$stats_dir/$name"
    ) &
    echo "$!" >> "$pids_file"
}

discover_subdomains() {
    local input="$1"
    local depth="${2:-1}"
    local results_dir="$TEMP_DIR/discovery_d${depth}"
    local stats_dir="$TEMP_DIR/stats_d${depth}"
    local pids_file="$TEMP_DIR/pids_d${depth}.txt"
    mkdir -p "$results_dir" "$stats_dir"
    
    if [[ $depth -eq 1 ]]; then
        section "SUBDOMAIN DISCOVERY (${SCAN_MODE^^})"
    else
        info "=== Recursive pass $depth ==="
    fi
    
    local tool_timeout
    tool_timeout=$(get_tool_timeout)
    info "$(count_lines "$input") domain(s) - Mode: ${SCAN_MODE} - Timeout: ${tool_timeout}s/domain"
    log ""
    
    > "$pids_file"
    local tools_launched=0
    
    # ==================== PASSIVE TOOLS ====================
    
    # Subfinder (tier 1)
    # In deep mode: uses -all flag to query all sources (slow but thorough)
    # In other modes: default sources only
    if should_run "subfinder" && tool_exists subfinder; then
        (
            local out="$results_dir/subfinder.txt"
            local err="$results_dir/subfinder.err"
            local start; start=$(date +%s)
            > "$out"
            local subfinder_flags="-silent"
            [[ "$SCAN_MODE" == "deep" ]] && subfinder_flags="-all -silent"
            
            while IFS= read -r domain; do
                timeout "$tool_timeout" subfinder -d "$domain" $subfinder_flags 2>>"$err" >> "$out"
            done < "$input"
            sort -u "$out" -o "$out" 2>/dev/null
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            local status="ok"
            local errmsg=""
            if [[ $count -eq 0 ]]; then
                errmsg=$(grep -i "error\|could not\|rate" "$err" 2>/dev/null | head -1 | cut -c1-60)
            fi
            echo "${status}:${count}:${elapsed}:${errmsg}" > "$stats_dir/subfinder"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    fi
    
    # Findomain (tier 1)
    if should_run "findomain" && tool_exists findomain; then
        (
            local out="$results_dir/findomain.txt"
            local err="$results_dir/findomain.err"
            local start; start=$(date +%s)
            > "$out"
            while IFS= read -r domain; do
                timeout "$tool_timeout" findomain -t "$domain" -q 2>>"$err" >> "$out"
            done < "$input"
            sort -u "$out" -o "$out" 2>/dev/null
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            local errmsg=""
            [[ $count -eq 0 ]] && errmsg=$(grep -i "error" "$err" 2>/dev/null | head -1 | cut -c1-60)
            echo "ok:${count}:${elapsed}:${errmsg}" > "$stats_dir/findomain"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    fi
    
    # Amass (tier 3 — slow, only in deep mode)
    if should_run "amass" && tool_exists amass; then
        (
            local out="$results_dir/amass.txt"
            local err="$results_dir/amass.err"
            local start; start=$(date +%s)
            > "$out"
            local amass_timeout=$((tool_timeout < 180 ? tool_timeout : 180))
            
            while IFS= read -r domain; do
                local tmp_out="$TEMP_DIR/amass_${domain}.txt"
                timeout "$amass_timeout" amass enum -passive -d "$domain" -o "$tmp_out" 2>>"$err"
                [[ -s "$tmp_out" ]] && cat "$tmp_out" >> "$out"
                rm -f "$tmp_out"
            done < "$input"
            sort -u "$out" -o "$out" 2>/dev/null
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            local status="ok"
            local errmsg=""
            if [[ $count -eq 0 ]]; then
                errmsg=$(grep -i "error\|failed" "$err" 2>/dev/null | head -1 | cut -c1-60)
            fi
            echo "${status}:${count}:${elapsed}:${errmsg}" > "$stats_dir/amass"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    fi
    
    # Assetfinder (tier 1)
    if should_run "assetfinder" && tool_exists assetfinder; then
        (
            local out="$results_dir/assetfinder.txt"
            local start; start=$(date +%s)
            > "$out"
            while IFS= read -r domain; do
                timeout 30 assetfinder --subs-only "$domain" 2>/dev/null >> "$out"
            done < "$input"
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            echo "ok:${count}:${elapsed}:" > "$stats_dir/assetfinder"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    fi
    
    # Sublist3r (tier 2)
    if should_run "sublist3r" && tool_exists sublist3r; then
        (
            local out="$results_dir/sublist3r.txt"
            local start; start=$(date +%s)
            > "$out"
            while IFS= read -r domain; do
                local tmp; tmp=$(mktemp)
                timeout "$tool_timeout" sublist3r -d "$domain" -o "$tmp" >/dev/null 2>&1
                [[ -s "$tmp" ]] && cat "$tmp" >> "$out"
                rm -f "$tmp"
            done < "$input"
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            echo "ok:${count}:${elapsed}:" > "$stats_dir/sublist3r"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    fi
    
    # Gau (tier 2) — extract subdomains from URLs
    if should_run "gau" && tool_exists gau; then
        (
            local out="$results_dir/gau.txt"
            local start; start=$(date +%s)
            > "$out"
            while IFS= read -r domain; do
                timeout "$tool_timeout" gau --subs "$domain" 2>/dev/null | \
                    sed -E 's|https?://||' | sed 's|/.*||' | sed 's|:.*||' | \
                    tr '[:upper:]' '[:lower:]' | \
                    grep -E "\.${domain}$|^${domain}$" >> "$out"
            done < "$input"
            sort -u "$out" -o "$out" 2>/dev/null
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            echo "ok:${count}:${elapsed}:" > "$stats_dir/gau"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    fi
    
    # Waybackurls
    if should_run "waybackurls" && tool_exists waybackurls; then
        (
            local out="$results_dir/waybackurls.txt"
            local start; start=$(date +%s)
            > "$out"
            while IFS= read -r domain; do
                timeout "$tool_timeout" waybackurls "$domain" 2>/dev/null | \
                    sed -E 's|https?://||' | sed 's|/.*||' | sed 's|:.*||' | \
                    tr '[:upper:]' '[:lower:]' | \
                    grep -E "\.${domain}$|^${domain}$" >> "$out"
            done < "$input"
            sort -u "$out" -o "$out" 2>/dev/null
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            echo "ok:${count}:${elapsed}:" > "$stats_dir/waybackurls"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    fi
    
    # Github-subdomains
    if should_run "github-subdomains" && tool_exists github-subdomains; then
        (
            local out="$results_dir/github.txt"
            local err="$results_dir/github.err"
            local start; start=$(date +%s)
            > "$out"
            while IFS= read -r domain; do
                timeout "$tool_timeout" github-subdomains -d "$domain" -raw 2>>"$err" >> "$out"
            done < "$input"
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            local errmsg=""
            if [[ $count -eq 0 ]]; then
                errmsg=$(grep -i "token\|rate\|error" "$err" 2>/dev/null | head -1 | cut -c1-50)
                [[ -z "$errmsg" ]] && errmsg="GITHUB_TOKEN required"
            fi
            echo "ok:${count}:${elapsed}:${errmsg}" > "$stats_dir/github"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    fi
    
    # CRT.SH (tool or curl fallback)
    if should_run "crtsh" && tool_exists crtsh; then
        (
            local out="$results_dir/crtsh.txt"
            local start; start=$(date +%s)
            > "$out"
            while IFS= read -r domain; do
                timeout "$tool_timeout" crtsh "$domain" 2>/dev/null >> "$out"
            done < "$input"
            sort -u "$out" -o "$out" 2>/dev/null
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            echo "ok:${count}:${elapsed}:" > "$stats_dir/crtsh"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    elif should_run "crtsh" && tool_exists curl; then
        # CRT.SH via curl API fallback
        (
            local out="$results_dir/crtsh.txt"
            local start; start=$(date +%s)
            > "$out"
            while IFS= read -r domain; do
                timeout 30 curl -s "https://crt.sh/?q=%25.${domain}&output=json" 2>/dev/null | \
                    grep -oE '"name_value":"[^"]*"' | \
                    sed 's/"name_value":"//;s/"$//' | \
                    sed 's/\\n/\n/g' | \
                    tr '[:upper:]' '[:lower:]' | \
                    sed 's/^\*\.//' | \
                    grep -E "\.${domain}$|^${domain}$" >> "$out"
                sleep 1  # Rate limit
            done < "$input"
            sort -u "$out" -o "$out" 2>/dev/null
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            echo "ok:${count}:${elapsed}:" > "$stats_dir/crtsh_curl"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    fi
    
    # OTX (AlienVault) — outputs full URLs, extract hostnames
    if should_run "otxurls" && tool_exists otxurls; then
        (
            local out="$results_dir/otxurls.txt"
            local start; start=$(date +%s)
            > "$out"
            while IFS= read -r domain; do
                timeout "$tool_timeout" otxurls "$domain" 2>/dev/null | \
                    sed -E 's|^https?://||' | \
                    sed 's|[/?#:].*||' | \
                    tr '[:upper:]' '[:lower:]' | \
                    grep -E "\.${domain}$|^${domain}$" >> "$out"
            done < "$input"
            sort -u "$out" -o "$out" 2>/dev/null
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            echo "ok:${count}:${elapsed}:" > "$stats_dir/otxurls"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    fi
    
    # Archive.org CDX — outputs full URLs, extract hostnames
    if should_run "archiveurls" && tool_exists archiveurls; then
        (
            local out="$results_dir/archiveurls.txt"
            local start; start=$(date +%s)
            > "$out"
            while IFS= read -r domain; do
                timeout "$tool_timeout" archiveurls "$domain" 2>/dev/null | \
                    sed -E 's|^https?://||' | \
                    sed 's|[/?#:].*||' | \
                    tr '[:upper:]' '[:lower:]' | \
                    grep -E "\.${domain}$|^${domain}$" >> "$out"
            done < "$input"
            sort -u "$out" -o "$out" 2>/dev/null
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            echo "ok:${count}:${elapsed}:" > "$stats_dir/archiveurls"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    fi
    
    # DNSDumpster — output format varies by implementation, extract valid hostnames
    if should_run "dnsdumpster" && tool_exists dnsdumpster; then
        (
            local out="$results_dir/dnsdumpster.txt"
            local err="$results_dir/dnsdumpster.err"
            local raw="$results_dir/dnsdumpster_raw.txt"
            local start; start=$(date +%s)
            > "$out"
            > "$raw"
            while IFS= read -r domain; do
                timeout "$tool_timeout" dnsdumpster "$domain" 2>>"$err" >> "$raw"
            done < "$input"
            # Extract any hostnames from the output (handles various output formats)
            if [[ -s "$raw" ]]; then
                while IFS= read -r domain; do
                    grep -oiE "[a-zA-Z0-9._-]+\\.${domain}" "$raw" >> "$out"
                done < "$input"
            fi
            sort -u "$out" -o "$out" 2>/dev/null
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            local errmsg=""
            [[ $count -eq 0 && -s "$err" ]] && errmsg=$(head -1 "$err" | cut -c1-60)
            echo "ok:${count}:${elapsed}:${errmsg}" > "$stats_dir/dnsdumpster"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    fi
    
    # Chaos
    if should_run "chaos" && tool_exists chaos && [[ -n "${PDCP_API_KEY:-}" ]]; then
        (
            local out="$results_dir/chaos.txt"
            local start; start=$(date +%s)
            > "$out"
            while IFS= read -r domain; do
                timeout 30 chaos -d "$domain" -silent 2>/dev/null >> "$out"
            done < "$input"
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            echo "ok:${count}:${elapsed}:" > "$stats_dir/chaos"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    fi
    
    # OneForAll
    # OneForAll (tier 3 — slow, only in deep mode)
    local oneforall_cmd=""
    if should_run "oneforall"; then
        tool_exists oneforall && oneforall_cmd="oneforall"
        [[ -z "$oneforall_cmd" && -f "$HOME/OneForAll/oneforall.py" ]] && oneforall_cmd="python3 $HOME/OneForAll/oneforall.py"
        [[ -z "$oneforall_cmd" && -f "/opt/OneForAll/oneforall.py" ]] && oneforall_cmd="python3 /opt/OneForAll/oneforall.py"
    fi
    
    if [[ -n "$oneforall_cmd" ]]; then
        (
            local out="$results_dir/oneforall.txt"
            local err="$results_dir/oneforall.err"
            local ofa_tmp="$TEMP_DIR/oneforall_d${depth}"
            mkdir -p "$ofa_tmp"
            local start; start=$(date +%s)
            > "$out"
            
            while IFS= read -r domain; do
                timeout "$tool_timeout" $oneforall_cmd --target "$domain" --path "$ofa_tmp" --fmt csv --dns False --brute False --req False run 2>>"$err" >/dev/null
            done < "$input"
            
            find "$ofa_tmp" -name "*.csv" -exec cat {} \; 2>/dev/null | \
                grep -v "^subdomain," | grep -v "^url," | cut -d',' -f1 | \
                grep -E '^[a-zA-Z0-9]' | sort -u > "$out"
            
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            local errmsg=""
            [[ $count -eq 0 ]] && errmsg=$(grep -i "error\|exception" "$err" 2>/dev/null | head -1 | cut -c1-50)
            echo "ok:${count}:${elapsed}:${errmsg}" > "$stats_dir/oneforall"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    fi
    
    # ==================== INTELLIGENCE TOOLS ====================
    
    # Shodan
    # Output format: "subdomain   TYPE   value" — first column is the subdomain
    # Requires: shodan init <API_KEY> to be configured
    if should_run "shodan" && tool_exists shodan; then
        (
            local out="$results_dir/shodan.txt"
            local err="$results_dir/shodan.err"
            local start; start=$(date +%s)
            > "$out"
            
            # Check if shodan is initialized
            if ! shodan info >/dev/null 2>&1; then
                echo "fail:0:0:API key not configured (run: shodan init <KEY>)" > "$stats_dir/shodan"
                exit 0
            fi
            
            while IFS= read -r domain; do
                # shodan domain outputs lines like:
                # DOMAIN.COM
                # sub1.domain.com    A    1.2.3.4
                # sub2.domain.com    CNAME    target.com
                timeout "$tool_timeout" shodan domain "$domain" 2>>"$err" | \
                    awk '{print $1}' | \
                    tr '[:upper:]' '[:lower:]' | \
                    grep -E "\\.${domain}$|^${domain}$" >> "$out"
            done < "$input"
            sort -u "$out" -o "$out" 2>/dev/null
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            local errmsg=""
            if [[ $count -eq 0 ]]; then
                errmsg=$(grep -i "error\|upgrade\|access denied\|rate" "$err" 2>/dev/null | head -1 | cut -c1-60)
                [[ -z "$errmsg" ]] && errmsg="no results (check plan/credits)"
            fi
            echo "ok:${count}:${elapsed}:${errmsg}" > "$stats_dir/shodan"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    fi
    
    # Censys
    # CLI command: censys subdomains <domain>
    # Requires: CENSYS_API_ID and CENSYS_API_SECRET configured
    if should_run "censys" && tool_exists censys; then
        (
            local out="$results_dir/censys.txt"
            local err="$results_dir/censys.err"
            local start; start=$(date +%s)
            > "$out"
            
            # Check if censys is configured
            if [[ -z "${CENSYS_API_ID:-}" || -z "${CENSYS_API_SECRET:-}" ]]; then
                if ! censys account 2>/dev/null | grep -q "login"; then
                    # Try running anyway, it might be configured via config file
                    :
                fi
            fi
            
            while IFS= read -r domain; do
                # censys subdomains outputs one subdomain per line
                timeout "$tool_timeout" censys subdomains "$domain" 2>>"$err" | \
                    tr '[:upper:]' '[:lower:]' | \
                    grep -E "\\.$domain$|^$domain$" >> "$out"
            done < "$input"
            sort -u "$out" -o "$out" 2>/dev/null
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            local errmsg=""
            if [[ $count -eq 0 ]]; then
                errmsg=$(grep -iE "error|unauthorized|invalid|API" "$err" 2>/dev/null | head -1 | cut -c1-60)
                [[ -z "$errmsg" ]] && errmsg="no results (check CENSYS_API_ID/SECRET)"
            fi
            echo "ok:${count}:${elapsed}:${errmsg}" > "$stats_dir/censys"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    fi
    
    # ==================== DNS TOOLS ====================
    
    local common_subs="www mail ftp admin api dev test staging blog shop app cdn vpn ns1 ns2 mx smtp webmail portal gitlab jenkins jira wiki docs status beta alpha demo uat pre prod int internal stage stg qa ci cd monitoring grafana kibana elastic db mysql redis mongo cache queue worker cron backup"
    
    if should_run "dig" && tool_exists dig; then
        (
            local out="$results_dir/dig.txt"
            local start; start=$(date +%s)
            > "$out"
            while IFS= read -r domain; do
                # Zone transfer attempt (AXFR)
                for ns in $(dig +short NS "$domain" 2>/dev/null | head -3); do
                    timeout 5 dig @"$ns" "$domain" AXFR +noall +answer 2>/dev/null | \
                        grep -oiE "[a-zA-Z0-9.-]+\.$domain" >> "$out"
                done
                # Common subdomains
                for sub in $common_subs; do
                    timeout 2 dig +short "$sub.$domain" A 2>/dev/null | grep -q '^[0-9]' && echo "$sub.$domain" >> "$out"
                done
            done < "$input"
            sort -u "$out" -o "$out" 2>/dev/null
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            echo "ok:${count}:${elapsed}:" > "$stats_dir/dig"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    fi
    
    if should_run "host" && tool_exists host; then
        (
            local out="$results_dir/host.txt"
            local start; start=$(date +%s)
            > "$out"
            while IFS= read -r domain; do
                for sub in $common_subs; do
                    timeout 2 host "$sub.$domain" 2>/dev/null | grep -q "has address" && echo "$sub.$domain" >> "$out"
                done
            done < "$input"
            sort -u "$out" -o "$out" 2>/dev/null
            local elapsed=$(( $(date +%s) - start ))
            local count=0; [[ -s "$out" ]] && count=$(wc -l < "$out" | tr -d ' ')
            echo "ok:${count}:${elapsed}:" > "$stats_dir/host"
        ) &
        echo "$!" >> "$pids_file"
        ((tools_launched++))
    fi
    
    [[ $tools_launched -eq 0 ]] && die "No discovery tool available"
    
    info "$tools_launched tools launched in parallel..."
    log ""
    
    # ==================== WAIT WITH LIVE DISPLAY ====================
    
    wait_for_tools "$pids_file" "$stats_dir"
    
    # ==================== COMBINE & CLEAN ====================
    
    log ""
    info "Combining results..."
    
    local combined="$TEMP_DIR/combined_d${depth}.txt"
    
    cat "$results_dir"/*.txt 2>/dev/null | \
        tr -d '\r' | \
        tr '[:upper:]' '[:lower:]' | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
        sed 's/^\*\.//' | \
        grep -E '^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$' | \
        sort -u > "$combined"
    
    # Scope validation
    local in_scope="$TEMP_DIR/inscope_d${depth}.txt"
    filter_in_scope "$combined" "$in_scope"
    
    local raw_count out_scope_count
    raw_count=$(count_lines "$combined")
    local inscope_count
    inscope_count=$(count_lines "$in_scope")
    out_scope_count=$((raw_count - inscope_count))
    
    info "$raw_count raw subdomains collected"
    [[ $out_scope_count -gt 0 ]] && warn "$out_scope_count out-of-scope entries removed"
    info "$inscope_count in-scope subdomains"
    
    # Merge with main file
    if [[ -s "$TEMP_DIR/all_subs.txt" ]]; then
        cat "$in_scope" >> "$TEMP_DIR/all_subs.txt"
        sort -u "$TEMP_DIR/all_subs.txt" -o "$TEMP_DIR/all_subs.txt"
    else
        cp "$in_scope" "$TEMP_DIR/all_subs.txt"
    fi
    
    TOTAL_PASSIVE_SUBS=$(count_lines "$TEMP_DIR/all_subs.txt")
}

wait_for_tools() {
    local pids_file="$1"
    local stats_dir="$2"
    local displayed=""
    
    while true; do
        local all_done=true
        while read -r pid; do
            [[ -z "$pid" ]] && continue
            kill -0 "$pid" 2>/dev/null && all_done=false
        done < "$pids_file"
        
        # Display completed tools
        for stat_file in "$stats_dir"/*; do
            [[ -f "$stat_file" ]] || continue
            local tool_name
            tool_name=$(basename "$stat_file")
            echo "$displayed" | grep -q "^${tool_name}$" && continue
            
            local stats
            stats=$(cat "$stat_file" 2>/dev/null)
            [[ -z "$stats" ]] && continue
            
            IFS=':' read -r status count elapsed errmsg <<< "$stats"
            
            # Store for report
            TOOL_STATS["$tool_name"]="$stats"
            
            display_tool_result "$tool_name" "$status" "$count" "$elapsed" "$errmsg"
            displayed="${displayed}${tool_name}"$'\n'
        done
        
        [[ "$all_done" == true ]] && break
        sleep 0.3
    done
    
    # Display any remaining
    for stat_file in "$stats_dir"/*; do
        [[ -f "$stat_file" ]] || continue
        local tool_name
        tool_name=$(basename "$stat_file")
        echo "$displayed" | grep -q "^${tool_name}$" && continue
        
        local stats
        stats=$(cat "$stat_file" 2>/dev/null)
        [[ -z "$stats" ]] && continue
        
        IFS=':' read -r status count elapsed errmsg <<< "$stats"
        TOOL_STATS["$tool_name"]="$stats"
        display_tool_result "$tool_name" "$status" "$count" "$elapsed" "$errmsg"
    done
}

display_tool_result() {
    local tool_name="$1" status="$2" count="$3" elapsed="$4" errmsg="$5"
    
    local time_str
    time_str=$(human_duration "$elapsed")
    
    case "$status" in
        timeout)
            log "  ${RED}✗${NC} ${tool_name}: ${RED}TIMEOUT${NC} (${time_str})" ;;
        fail)
            log "  ${RED}✗${NC} ${tool_name}: ${RED}FAILED${NC} - ${errmsg:-error} (${time_str})" ;;
        *)
            if [[ "$count" -gt 0 ]]; then
                log "  ${GREEN}✓${NC} ${tool_name}: ${GREEN}${count}${NC} found (${time_str})"
            elif [[ -n "$errmsg" ]]; then
                log "  ${YEL}○${NC} ${tool_name}: 0 found - ${errmsg} (${time_str})"
            else
                log "  ${YEL}○${NC} ${tool_name}: 0 found (${time_str})"
            fi ;;
    esac
}

# ==========================================================
# DNS RESOLUTION
# ==========================================================

resolve_subdomains() {
    local subs_file="$1"
    
    ! $RESOLVE_ALL && return 0
    
    local count
    count=$(count_lines "$subs_file")
    [[ $count -eq 0 ]] && return 0
    
    info "DNS resolution of $count subdomains..."
    
    if tool_exists dnsx; then
        local resolved="$TEMP_DIR/resolved.txt"
        cat "$subs_file" | dnsx -silent -t "$THREADS" -retry 2 > "$resolved" 2>/dev/null
        
        local resolved_count
        resolved_count=$(count_lines "$resolved")
        
        if [[ $resolved_count -gt 0 ]]; then
            ok "$resolved_count subdomains resolved (dnsx)"
            mv "$resolved" "$subs_file"
            TOTAL_RESOLVED=$resolved_count
        else
            warn "dnsx resolved 0, keeping raw results"
            rm -f "$resolved"
            TOTAL_RESOLVED=$count
        fi
    elif tool_exists massdns; then
        local resolvers="$TEMP_DIR/resolvers_dns.txt"
        echo -e "8.8.8.8\n1.1.1.1\n9.9.9.9\n8.8.4.4\n1.0.0.1" > "$resolvers"
        
        local resolved="$TEMP_DIR/resolved.txt"
        massdns -r "$resolvers" -t A -o S "$subs_file" 2>/dev/null | \
            awk '{print $1}' | sed 's/\.$//' | sort -u > "$resolved"
        
        local resolved_count
        resolved_count=$(count_lines "$resolved")
        
        if [[ $resolved_count -gt 0 ]]; then
            ok "$resolved_count subdomains resolved (massdns)"
            mv "$resolved" "$subs_file"
            TOTAL_RESOLVED=$resolved_count
        else
            warn "massdns resolved 0, keeping raw results"
            rm -f "$resolved"
            TOTAL_RESOLVED=$count
        fi
    else
        debug "No DNS resolution tool available (dnsx/massdns)"
        TOTAL_RESOLVED=$count
    fi
}

# ==========================================================
# DNS BRUTEFORCE
# ==========================================================

bruteforce_subdomains() {
    [[ -z "$WORDLIST" || ! -f "$WORDLIST" ]] && return 0
    
    section "DNS BRUTEFORCE"
    
    local wordcount
    wordcount=$(count_lines "$WORDLIST")
    info "Wordlist: $(basename "$WORDLIST") ($wordcount words)"
    log ""
    
    local brute_out="$TEMP_DIR/brute.txt"
    > "$brute_out"
    
    local before_count
    before_count=$(count_lines "$TEMP_DIR/all_subs.txt")
    
    # PureDNS (best option)
    if tool_exists puredns; then
        info "Running puredns..."
        while IFS= read -r domain; do
            timeout 300 puredns bruteforce "$WORDLIST" "$domain" -q 2>/dev/null >> "$brute_out"
        done < "$INPUT_FILE"
        local count
        count=$(count_lines "$brute_out")
        [[ $count -gt 0 ]] && ok "puredns: $count found"
    fi
    
    # Shuffledns
    if tool_exists shuffledns && tool_exists massdns; then
        info "Running shuffledns..."
        local resolvers="$TEMP_DIR/resolvers_brute.txt"
        echo -e "8.8.8.8\n1.1.1.1\n9.9.9.9\n8.8.4.4\n1.0.0.1" > "$resolvers"
        while IFS= read -r domain; do
            timeout 300 shuffledns -d "$domain" -w "$WORDLIST" -r "$resolvers" -silent 2>/dev/null >> "$brute_out"
        done < "$INPUT_FILE"
    fi
    
    # Gobuster
    if tool_exists gobuster; then
        info "Running gobuster..."
        while IFS= read -r domain; do
            timeout 300 gobuster dns -d "$domain" -w "$WORDLIST" -q --no-color 2>/dev/null | \
                grep -oE "Found: [a-zA-Z0-9.-]+" | sed 's/Found: //' >> "$brute_out"
        done < "$INPUT_FILE"
    fi
    
    # DMUT (permutations on existing subdomains)
    if tool_exists dmut && [[ -s "$TEMP_DIR/all_subs.txt" ]]; then
        info "Running dmut (permutations)..."
        cat "$TEMP_DIR/all_subs.txt" | dmut -d "$WORDLIST" -w 50 --dns-retries 3 -s 2>/dev/null | \
            grep -v "^\[" >> "$brute_out" 2>/dev/null || true
    fi
    
    # Gotator (permutations on existing subdomains)
    if tool_exists gotator && [[ -s "$TEMP_DIR/all_subs.txt" ]]; then
        info "Running gotator (permutations)..."
        local gotator_out="$TEMP_DIR/gotator.txt"
        gotator -sub "$TEMP_DIR/all_subs.txt" -perm "$WORDLIST" -depth 1 -numbers 3 -mindup -adv -silent 2>/dev/null > "$gotator_out" || true
        if [[ -s "$gotator_out" ]]; then
            if tool_exists dnsx; then
                cat "$gotator_out" | dnsx -silent -t "$THREADS" >> "$brute_out" 2>/dev/null
            elif tool_exists puredns; then
                cat "$gotator_out" | puredns resolve -q >> "$brute_out" 2>/dev/null
            fi
        fi
    fi
    
    # Alterx (newer alternative to gotator)
    if tool_exists alterx && [[ -s "$TEMP_DIR/all_subs.txt" ]]; then
        info "Running alterx (permutations)..."
        local alterx_out="$TEMP_DIR/alterx.txt"
        cat "$TEMP_DIR/all_subs.txt" | alterx -silent 2>/dev/null > "$alterx_out" || true
        if [[ -s "$alterx_out" ]]; then
            if tool_exists dnsx; then
                cat "$alterx_out" | dnsx -silent -t "$THREADS" >> "$brute_out" 2>/dev/null
            elif tool_exists puredns; then
                cat "$alterx_out" | puredns resolve -q >> "$brute_out" 2>/dev/null
            fi
        fi
    fi
    
    # Scope validation + merge
    if [[ -s "$brute_out" ]]; then
        local brute_inscope="$TEMP_DIR/brute_inscope.txt"
        filter_in_scope "$brute_out" "$brute_inscope"
        sort -u "$brute_inscope" -o "$brute_inscope"
        
        local brute_count
        brute_count=$(count_lines "$brute_inscope")
        ok "Bruteforce: $brute_count in-scope subdomains"
        
        cat "$brute_inscope" >> "$TEMP_DIR/all_subs.txt"
        sort -u "$TEMP_DIR/all_subs.txt" -o "$TEMP_DIR/all_subs.txt"
        
        local after_count
        after_count=$(count_lines "$TEMP_DIR/all_subs.txt")
        local new_count=$((after_count - before_count))
        TOTAL_BRUTE_SUBS=$new_count
        info "$new_count new unique subdomains from bruteforce"
    fi
}

# ==========================================================
# RECURSIVE DISCOVERY
# ==========================================================

recursive_discovery() {
    ! $RECURSIVE && return 0
    [[ ! -s "$TEMP_DIR/all_subs.txt" ]] && return 0
    
    local depth=2
    
    while [[ $depth -le $MAX_RECURSIVE_DEPTH ]]; do
        local prev_count
        prev_count=$(count_lines "$TEMP_DIR/all_subs.txt")
        
        # Use discovered subdomains as new input for discovery
        info "Recursive pass $depth (input: $prev_count subdomains)..."
        
        # Extract unique parent-like domains (2nd level subs)
        local recursive_input="$TEMP_DIR/recursive_input_d${depth}.txt"
        awk -F. '{
            n=NF;
            if (n >= 3) {
                # Get the parent of each subdomain
                result = ""
                for (i=2; i<=n; i++) {
                    if (result != "") result = result "."
                    result = result $i
                }
                print result
            }
        }' "$TEMP_DIR/all_subs.txt" | sort -u > "$recursive_input"
        
        # Also include original domains
        cat "$TEMP_DIR/parent_domains.txt" >> "$recursive_input"
        sort -u "$recursive_input" -o "$recursive_input"
        
        discover_subdomains "$recursive_input" "$depth"
        
        local new_count
        new_count=$(count_lines "$TEMP_DIR/all_subs.txt")
        local added=$((new_count - prev_count))
        
        if [[ $added -le 0 ]]; then
            info "Recursive pass $depth: no new subdomains, stopping"
            break
        fi
        
        info "Recursive pass $depth: $added new subdomains"
        ((depth++))
    done
}

# ==========================================================
# ORGANIZE RESULTS BY DOMAIN
# ==========================================================

organize_results() {
    log ""
    info "Organizing results by domain..."
    
    local parents="$TEMP_DIR/parent_domains.txt"
    
    while IFS= read -r parent; do
        local out_file="$OUTPUT_DIR/${parent}.txt"
        
        grep -iE "(^https?://${parent}/|^https?://[a-z0-9.-]+\.${parent}/)" "$OUTPUT_FILE" 2>/dev/null > "$out_file" || true
        
        local count=0
        [[ -s "$out_file" ]] && count=$(count_lines "$out_file")
        
        if [[ $count -gt 0 ]]; then
            ok "$parent: $count URLs"
        else
            rm -f "$out_file"
        fi
    done < "$parents"
    
    local files_created
    files_created=$(find "$OUTPUT_DIR" -name "*.txt" -size +0 2>/dev/null | wc -l)
    info "$files_created domain files created in $OUTPUT_DIR"
}

# ==========================================================
# HTTP SCAN
# ==========================================================

scan_http() {
    local scanlist="$1"
    
    section "HTTP SCAN"
    
    local total
    total=$(count_lines "$scanlist")
    info "$total domains to scan ($THREADS threads)"
    info "Mode: follow redirects → accept only final HTTP ${HTTP_ACCEPT} → output final URL"
    log ""
    
    > "$OUTPUT_FILE"
    
    if $USE_HTTPX && [[ -n "$HTTPX_BIN" ]]; then
        scan_with_httpx "$scanlist"
    else
        scan_with_curl "$scanlist"
    fi
    
    # Post-filter: remove URLs that redirected to blacklisted domains
    if [[ -s "$OUTPUT_FILE" && -n "$BLACKLIST_PATTERN" ]]; then
        local before_filter
        before_filter=$(count_lines "$OUTPUT_FILE")
        local filtered="$TEMP_DIR/output_filtered.txt"
        
        while IFS= read -r url; do
            local host="${url#http*://}"
            host="${host%%/*}"
            host="${host%%:*}"
            if ! echo "$host" | grep -qiE "$BLACKLIST_PATTERN"; then
                echo "$url"
            fi
        done < "$OUTPUT_FILE" > "$filtered"
        
        mv "$filtered" "$OUTPUT_FILE"
        local after_filter
        after_filter=$(count_lines "$OUTPUT_FILE")
        local removed=$((before_filter - after_filter))
        [[ $removed -gt 0 ]] && info "$removed URLs removed (redirected to blacklisted domains)"
    fi
    
    TOTAL_LIVE=$(count_lines "$OUTPUT_FILE")
    
    if [[ $TOTAL_LIVE -gt 0 ]]; then
        ok "$TOTAL_LIVE live URLs found"
    else
        warn "No live URL found"
        debug_scan "$scanlist"
    fi
}

scan_with_httpx() {
    local scanlist="$1"
    info "Scanning with httpx (ProjectDiscovery)..."
    info "Strategy: follow redirects → only keep final HTTP ${HTTP_ACCEPT} → output final URL"
    
    local httpx_input="$TEMP_DIR/httpx_input.txt"
    local httpx_raw="$TEMP_DIR/httpx_raw.txt"
    
    # Generate both http and https URLs
    sed 's|^|https://|' "$scanlist" > "$httpx_input"
    sed 's|^|http://|' "$scanlist" >> "$httpx_input"
    
    # httpx: follow redirects, match only final accepted codes, output the final location
    "$HTTPX_BIN" -l "$httpx_input" \
        -threads "$THREADS" \
        -timeout "$TIMEOUT_CURL" \
        -no-color \
        -silent \
        -follow-redirects \
        -mc "$(echo "$HTTP_ACCEPT" | tr '|' ',')" \
        -location \
        2>/dev/null > "$httpx_raw"
    
    # httpx with -location outputs: original_url [final_url]
    # We want the final URL (or original if no redirect)
    if [[ -s "$httpx_raw" ]]; then
        awk '{
            # If there is a second field (redirect location), use it
            if ($2 != "" && $2 ~ /^https?:\/\//) {
                print $2
            } else {
                print $1
            }
        }' "$httpx_raw" | \
            sed 's|/*$|/|' | sed 's|//$|/|' | \
            grep -v '^$' | sort -u > "$OUTPUT_FILE"
    fi
    
    # If still nothing, try probe mode with status filter
    if [[ ! -s "$OUTPUT_FILE" ]]; then
        warn "httpx list mode: 0 results, trying probe mode..."
        cat "$scanlist" | "$HTTPX_BIN" \
            -probe \
            -threads "$THREADS" \
            -timeout "$TIMEOUT_CURL" \
            -no-color \
            -silent \
            -follow-redirects \
            -mc "$(echo "$HTTP_ACCEPT" | tr '|' ',')" \
            2>/dev/null | \
            sed 's|/*$|/|' | sed 's|//$|/|' | \
            grep -v '^$' | sort -u > "$OUTPUT_FILE"
    fi
    
    # Verbose: save detailed output with status codes for debugging
    if $VERBOSE && [[ -n "$HTTPX_BIN" ]]; then
        local detail_file="${OUTPUT_FILE%.txt}_httpx_detail.txt"
        "$HTTPX_BIN" -l "$httpx_input" \
            -threads "$THREADS" \
            -timeout "$TIMEOUT_CURL" \
            -no-color \
            -silent \
            -follow-redirects \
            -status-code \
            -title \
            -tech-detect \
            -content-length \
            -location \
            2>/dev/null > "$detail_file"
        
        [[ -s "$detail_file" ]] && debug "Detailed httpx output: $detail_file"
    fi
}

scan_with_curl() {
    local scanlist="$1"
    info "Scanning with curl ($THREADS parallel, ${TIMEOUT_CURL}s timeout)..."
    info "Strategy: follow redirects → only keep final HTTP ${HTTP_ACCEPT} → output final URL"
    
    export BLACKLIST_PATTERN USER_AGENT TIMEOUT_CURL HTTP_ACCEPT
    
    cat "$scanlist" | xargs -P "$THREADS" -I {} bash -c '
        domain="{}"
        [[ -z "$domain" ]] && exit 0
        
        # Pre-filter: skip blacklisted input domains
        [[ -n "$BLACKLIST_PATTERN" ]] && echo "$domain" | grep -qiE "$BLACKLIST_PATTERN" && exit 0
        
        check_result() {
            local code="$1" final_url="$2"
            # Must match accepted status code
            [[ ! "$code" =~ ^($HTTP_ACCEPT)$ ]] && return 1
            # Post-filter: reject if final URL landed on a blacklisted domain
            if [[ -n "$BLACKLIST_PATTERN" ]]; then
                local final_host="${final_url#http*://}"
                final_host="${final_host%%/*}"
                final_host="${final_host%%:*}"
                echo "$final_host" | grep -qiE "$BLACKLIST_PATTERN" && return 1
            fi
            return 0
        }
        
        try_url() {
            local url="$1"
            local result code final_url
            result=$(curl -skL -o /dev/null -w "%{http_code}|%{url_effective}" \
                --max-time "$TIMEOUT_CURL" --connect-timeout 8 \
                --max-redirs 10 \
                -A "$USER_AGENT" "$url" 2>/dev/null)
            code="${result%%|*}"
            final_url="${result##*|}"
            
            if check_result "$code" "$final_url"; then
                echo "$final_url" | sed "s|/*$|/|" | sed "s|//$|/|"
                return 0
            fi
            return 1
        }
        
        # 1) Try HTTPS first
        try_url "https://$domain" && exit 0
        
        # 2) Fallback: try HTTP (handles SSL errors, HTTPS misconfigs, HTTP-only servers)
        try_url "http://$domain" && exit 0
        
    ' 2>/dev/null | sort -u > "$OUTPUT_FILE"
}

debug_scan() {
    local scanlist="$1"
    info "Debug: testing first 5 domains (showing redirect chain)..."
    head -5 "$scanlist" | while read -r d; do
        [[ -z "$d" ]] && continue
        # Show full redirect chain
        local result
        result=$(curl -skL -o /dev/null -w "code=%{http_code} url=%{url_effective} redirects=%{num_redirects}" \
            --max-time 10 --max-redirs 10 "https://$d" 2>/dev/null)
        local code url redirects
        code=$(echo "$result" | grep -oP 'code=\K[0-9]+')
        url=$(echo "$result" | grep -oP 'url=\K[^ ]+')
        redirects=$(echo "$result" | grep -oP 'redirects=\K[0-9]+')
        
        if [[ "$code" == "200" ]]; then
            log "    ${GREEN}✓${NC} $d → ${GREEN}200${NC} (${redirects} redirects) → $url"
        else
            log "    ${RED}✗${NC} $d → ${RED}${code}${NC} (${redirects} redirects) → $url"
        fi
    done
}

# ==========================================================
# REPORT GENERATION
# ==========================================================

generate_report() {
    ! $GENERATE_REPORT && return 0
    
    local report_file
    if [[ "$REPORT_FORMAT" == "json" ]]; then
        report_file="${OUTPUT_FILE%.txt}_report.json"
        generate_json_report "$report_file"
    else
        report_file="${OUTPUT_FILE%.txt}_report.html"
        generate_html_report "$report_file"
    fi
    
    ok "Report saved: $report_file"
}

generate_json_report() {
    local outfile="$1"
    local elapsed=$(($(date +%s) - SCAN_START_TIME))
    local total_subs
    total_subs=$(count_lines "$TEMP_DIR/all_subs.txt" 2>/dev/null || echo 0)
    
    # Build tools JSON array
    local tools_json="["
    local first=true
    for tool in "${!TOOL_STATS[@]}"; do
        local stats="${TOOL_STATS[$tool]}"
        IFS=':' read -r status count tel errmsg <<< "$stats"
        $first || tools_json+=","
        first=false
        tools_json+=$(printf '{"name":"%s","status":"%s","count":%s,"elapsed":%s,"error":"%s"}' \
            "$tool" "$status" "${count:-0}" "${tel:-0}" "${errmsg:-}")
    done
    tools_json+="]"
    
    # Build domains JSON
    local domains_json="["
    first=true
    local parents="$TEMP_DIR/parent_domains.txt"
    while IFS= read -r parent; do
        $first || domains_json+=","
        first=false
        local sub_count
        sub_count=$(grep -cE "\.${parent}$|^${parent}$" "$TEMP_DIR/all_subs.txt" 2>/dev/null || echo 0)
        local live_count
        live_count=$(grep -ciE "://${parent}/|://[a-z0-9.-]+\.${parent}/" "$OUTPUT_FILE" 2>/dev/null || echo 0)
        domains_json+=$(printf '{"domain":"%s","subdomains":%s,"live":%s}' "$parent" "$sub_count" "$live_count")
    done < "$parents"
    domains_json+="]"
    
    # Build live URLs JSON
    local urls_json="["
    first=true
    if [[ -s "$OUTPUT_FILE" ]]; then
        while IFS= read -r url; do
            $first || urls_json+=","
            first=false
            urls_json+="\"$url\""
        done < "$OUTPUT_FILE"
    fi
    urls_json+="]"
    
    # Wildcards
    local wc_json="["
    first=true
    for wc in "${WILDCARD_DOMAINS[@]}"; do
        $first || wc_json+=","
        first=false
        wc_json+="\"$wc\""
    done
    wc_json+="]"
    
    cat > "$outfile" <<JSONEOF
{
  "sAImap_version": "${VERSION}",
  "scan_date": "$(date -Iseconds)",
  "duration_seconds": $elapsed,
  "summary": {
    "input_domains": $(count_lines "$TEMP_DIR/parent_domains.txt"),
    "total_subdomains": $total_subs,
    "passive_subdomains": $TOTAL_PASSIVE_SUBS,
    "bruteforce_subdomains": $TOTAL_BRUTE_SUBS,
    "resolved": $TOTAL_RESOLVED,
    "live_urls": $TOTAL_LIVE,
    "wildcard_domains": ${#WILDCARD_DOMAINS[@]}
  },
  "wildcards": $wc_json,
  "tools": $tools_json,
  "domains": $domains_json,
  "live_urls": $urls_json
}
JSONEOF
}

generate_html_report() {
    local outfile="$1"
    local elapsed=$(($(date +%s) - SCAN_START_TIME))
    local elapsed_str
    elapsed_str=$(human_duration "$elapsed")
    local total_subs
    total_subs=$(count_lines "$TEMP_DIR/all_subs.txt" 2>/dev/null || echo 0)
    local input_count
    input_count=$(count_lines "$TEMP_DIR/parent_domains.txt")
    
    cat > "$outfile" <<'HTMLHEAD'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>sAImap Scan Report</title>
<style>
:root { --bg: #0d1117; --card: #161b22; --border: #30363d; --text: #e6edf3; --muted: #8b949e; --green: #3fb950; --red: #f85149; --yellow: #d29922; --blue: #58a6ff; --cyan: #39d353; }
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: 'Segoe UI', system-ui, -apple-system, sans-serif; background: var(--bg); color: var(--text); padding: 2rem; line-height: 1.6; }
.container { max-width: 1100px; margin: 0 auto; }
h1 { color: var(--cyan); font-size: 1.8rem; margin-bottom: 0.5rem; }
h2 { color: var(--blue); font-size: 1.3rem; margin: 2rem 0 1rem; border-bottom: 1px solid var(--border); padding-bottom: 0.5rem; }
.meta { color: var(--muted); font-size: 0.9rem; margin-bottom: 2rem; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
.stat-card { background: var(--card); border: 1px solid var(--border); border-radius: 8px; padding: 1.2rem; text-align: center; }
.stat-card .value { font-size: 2rem; font-weight: 700; color: var(--green); }
.stat-card .label { color: var(--muted); font-size: 0.85rem; margin-top: 0.3rem; }
table { width: 100%; border-collapse: collapse; margin: 1rem 0; background: var(--card); border-radius: 8px; overflow: hidden; }
th, td { padding: 0.7rem 1rem; text-align: left; border-bottom: 1px solid var(--border); }
th { background: #1c2128; color: var(--muted); font-weight: 600; font-size: 0.85rem; text-transform: uppercase; }
.status-ok { color: var(--green); }
.status-fail { color: var(--red); }
.status-warn { color: var(--yellow); }
.url-list { background: var(--card); border: 1px solid var(--border); border-radius: 8px; padding: 1rem; max-height: 400px; overflow-y: auto; font-family: monospace; font-size: 0.85rem; }
.url-list a { color: var(--blue); text-decoration: none; display: block; padding: 0.15rem 0; }
.url-list a:hover { text-decoration: underline; }
.badge { display: inline-block; padding: 0.15rem 0.5rem; border-radius: 4px; font-size: 0.75rem; font-weight: 600; }
.badge-green { background: rgba(63,185,80,0.2); color: var(--green); }
.badge-red { background: rgba(248,81,73,0.2); color: var(--red); }
.badge-yellow { background: rgba(210,153,34,0.2); color: var(--yellow); }
</style>
</head>
<body>
<div class="container">
HTMLHEAD

    # Header
    cat >> "$outfile" <<EOF
<h1>⚡ sAImap v${VERSION} - Scan Report</h1>
<p class="meta">Generated: $(date "+%Y-%m-%d %H:%M:%S") | Duration: ${elapsed_str}</p>
EOF

    # Summary cards
    cat >> "$outfile" <<EOF
<div class="grid">
<div class="stat-card"><div class="value">${input_count}</div><div class="label">Input Domains</div></div>
<div class="stat-card"><div class="value">${total_subs}</div><div class="label">Subdomains Found</div></div>
<div class="stat-card"><div class="value">${TOTAL_RESOLVED}</div><div class="label">Resolved</div></div>
<div class="stat-card"><div class="value" style="color:${TOTAL_LIVE:+var(--green)}">${TOTAL_LIVE}</div><div class="label">Live URLs</div></div>
</div>
EOF

    # Wildcard warning
    if [[ ${#WILDCARD_DOMAINS[@]} -gt 0 ]]; then
        echo '<div style="background:rgba(210,153,34,0.1);border:1px solid var(--yellow);border-radius:8px;padding:1rem;margin-bottom:1rem;">' >> "$outfile"
        echo "<strong style=\"color:var(--yellow)\">⚠ Wildcard DNS detected:</strong> " >> "$outfile"
        printf '%s\n' "${WILDCARD_DOMAINS[@]}" | sed 's|.*|<code>&</code>|' | tr '\n' ' ' >> "$outfile"
        echo '</div>' >> "$outfile"
    fi

    # Tools table
    echo '<h2>🛠 Tool Results</h2>' >> "$outfile"
    echo '<table><thead><tr><th>Tool</th><th>Status</th><th>Results</th><th>Time</th><th>Notes</th></tr></thead><tbody>' >> "$outfile"
    
    for tool in $(echo "${!TOOL_STATS[@]}" | tr ' ' '\n' | sort); do
        local stats="${TOOL_STATS[$tool]}"
        IFS=':' read -r status count tel errmsg <<< "$stats"
        
        local status_class="status-ok" status_text="✓ OK" badge_class="badge-green"
        case "$status" in
            timeout) status_class="status-fail"; status_text="✗ TIMEOUT"; badge_class="badge-red" ;;
            fail)    status_class="status-fail"; status_text="✗ FAILED"; badge_class="badge-red" ;;
            *)       [[ "${count:-0}" -eq 0 ]] && { status_class="status-warn"; status_text="○ Empty"; badge_class="badge-yellow"; } ;;
        esac
        
        local time_str
        time_str=$(human_duration "${tel:-0}")
        
        echo "<tr><td><strong>$tool</strong></td><td class=\"$status_class\">$status_text</td><td><span class=\"badge $badge_class\">${count:-0}</span></td><td>$time_str</td><td style=\"color:var(--muted);font-size:0.85rem\">${errmsg:-}</td></tr>" >> "$outfile"
    done
    echo '</tbody></table>' >> "$outfile"

    # Per-domain breakdown
    echo '<h2>🌐 Domains Breakdown</h2>' >> "$outfile"
    echo '<table><thead><tr><th>Domain</th><th>Subdomains</th><th>Live URLs</th></tr></thead><tbody>' >> "$outfile"
    
    local parents="$TEMP_DIR/parent_domains.txt"
    while IFS= read -r parent; do
        local sub_count
        sub_count=$(grep -cE "\.${parent}$|^${parent}$" "$TEMP_DIR/all_subs.txt" 2>/dev/null || echo 0)
        local live_count
        live_count=$(grep -ciE "://${parent}/|://[a-z0-9.-]+\.${parent}/" "$OUTPUT_FILE" 2>/dev/null || echo 0)
        echo "<tr><td><strong>$parent</strong></td><td>$sub_count</td><td><span class=\"badge badge-green\">$live_count</span></td></tr>" >> "$outfile"
    done < "$parents"
    echo '</tbody></table>' >> "$outfile"

    # Live URLs
    echo '<h2>🔗 Live URLs</h2>' >> "$outfile"
    echo '<div class="url-list">' >> "$outfile"
    if [[ -s "$OUTPUT_FILE" ]]; then
        while IFS= read -r url; do
            echo "<a href=\"$url\" target=\"_blank\" rel=\"noopener\">$url</a>" >> "$outfile"
        done < "$OUTPUT_FILE"
    else
        echo '<p style="color:var(--muted)">No live URLs found.</p>' >> "$outfile"
    fi
    echo '</div>' >> "$outfile"

    # Footer
    cat >> "$outfile" <<'HTMLFOOT'
</div>
</body>
</html>
HTMLFOOT
}

# ==========================================================
# WEBHOOK NOTIFICATION
# ==========================================================

send_webhook() {
    [[ -z "$WEBHOOK_URL" ]] && return 0
    ! tool_exists curl && return 0
    
    local elapsed=$(($(date +%s) - SCAN_START_TIME))
    local elapsed_str
    elapsed_str=$(human_duration "$elapsed")
    local input_count
    input_count=$(count_lines "$TEMP_DIR/parent_domains.txt")
    
    local payload
    payload=$(cat <<WEBHOOKEOF
{
  "text": "sAImap scan complete",
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*sAImap v${VERSION} - Scan Complete* ✅\n• Domains: ${input_count}\n• Subdomains: ${TOTAL_PASSIVE_SUBS}\n• Live URLs: *${TOTAL_LIVE}*\n• Duration: ${elapsed_str}\n• Output: \`${OUTPUT_FILE}\`"
      }
    }
  ]
}
WEBHOOKEOF
)
    
    curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$WEBHOOK_URL" >/dev/null 2>&1
    debug "Webhook notification sent"
}

# ==========================================================
# MAIN
# ==========================================================

main() {
    SCAN_START_TIME=$(date +%s)
    
    # Load config (before arg parsing so CLI overrides config)
    load_config
    
    # Parse arguments (overrides config)
    parse_args "$@"
    
    banner
    check_tools
    setup_blacklist
    prepare_input
    apply_scan_mode
    
    # Create output directory if specified
    if [[ -n "$OUTPUT_DIR" ]]; then
        mkdir -p "$OUTPUT_DIR"
        info "Output directory: $OUTPUT_DIR"
    fi
    
    # Initialize all_subs.txt
    > "$TEMP_DIR/all_subs.txt"
    
    local scanlist="$INPUT_FILE"
    
    # === Phase 1: Subdomain Discovery ===
    if $USE_DISCOVERY; then
        discover_subdomains "$INPUT_FILE"
        scanlist="$TEMP_DIR/all_subs.txt"
    fi
    
    # === Phase 2: DNS Bruteforce ===
    if [[ -n "$WORDLIST" && -f "$WORDLIST" ]]; then
        bruteforce_subdomains
        scanlist="$TEMP_DIR/all_subs.txt"
    fi
    
    # === Phase 3: Recursive Discovery ===
    if $RECURSIVE; then
        recursive_discovery
        scanlist="$TEMP_DIR/all_subs.txt"
    fi
    
    # === Phase 4: Wildcard Detection ===
    if [[ -s "$scanlist" ]] && $DETECT_WILDCARDS && $USE_DISCOVERY; then
        detect_wildcards "$scanlist"
    fi
    
    # === Phase 5: DNS Resolution ===
    if [[ -s "$scanlist" ]] && $RESOLVE_ALL && $USE_DISCOVERY; then
        resolve_subdomains "$scanlist"
    fi
    
    # If no discovery, scanlist is input
    [[ ! -s "$scanlist" ]] && scanlist="$INPUT_FILE"
    [[ ! -s "$scanlist" ]] && die "No domain to scan"
    
    # === Phase 6: Apply Blacklist ===
    local prescan="$TEMP_DIR/prescan.txt"
    > "$prescan"
    while IFS= read -r domain; do
        is_blacklisted "$domain" || echo "$domain" >> "$prescan"
    done < "$scanlist"
    
    [[ ! -s "$prescan" ]] && die "All domains filtered by blacklist"
    
    local final_count
    final_count=$(count_lines "$prescan")
    info "$final_count subdomains ready for HTTP scan"
    
    # === Phase 7: HTTP Scan ===
    scan_http "$prescan"
    
    # === Phase 8: Organize results ===
    if [[ -n "$OUTPUT_DIR" && -s "$OUTPUT_FILE" ]]; then
        organize_results
    fi
    
    # === Phase 9: Reports ===
    generate_report
    
    # === Phase 10: Save all subdomains file ===
    if [[ -s "$TEMP_DIR/all_subs.txt" ]]; then
        local subs_file="${OUTPUT_FILE%.txt}_subdomains.txt"
        cp "$TEMP_DIR/all_subs.txt" "$subs_file"
        debug "All subdomains saved: $subs_file"
    fi
    
    # === Final Summary ===
    local elapsed=$(($(date +%s) - SCAN_START_TIME))
    local elapsed_str
    elapsed_str=$(human_duration "$elapsed")
    
    log ""
    log "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    log "${CYAN}║${NC} ${GREEN}${BOLD}✓ SCAN COMPLETE${NC} in ${elapsed_str} (mode: ${SCAN_MODE})"
    log "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    log "${CYAN}║${NC}   Input domains:    $final_count"
    if $USE_DISCOVERY; then
    log "${CYAN}║${NC}   Subdomains found: ${GREEN}${TOTAL_PASSIVE_SUBS}${NC}"
    [[ $TOTAL_BRUTE_SUBS -gt 0 ]] && \
    log "${CYAN}║${NC}   Bruteforce added: ${GREEN}${TOTAL_BRUTE_SUBS}${NC}"
    [[ $TOTAL_RESOLVED -gt 0 ]] && \
    log "${CYAN}║${NC}   DNS resolved:     ${GREEN}${TOTAL_RESOLVED}${NC}"
    [[ ${#WILDCARD_DOMAINS[@]} -gt 0 ]] && \
    log "${CYAN}║${NC}   Wildcard domains: ${YEL}${#WILDCARD_DOMAINS[@]}${NC}"
    fi
    log "${CYAN}║${NC}   Live URLs:        ${GREEN}${BOLD}${TOTAL_LIVE}${NC}"
    log "${CYAN}║${NC}   Output:           ${OUTPUT_FILE}"
    [[ -n "$OUTPUT_DIR" ]] && \
    log "${CYAN}║${NC}   Directory:        ${OUTPUT_DIR}"
    $GENERATE_REPORT && \
    log "${CYAN}║${NC}   Report:           ${OUTPUT_FILE%.txt}_report.${REPORT_FORMAT}"
    log "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    log ""
    
    # Webhook notification
    send_webhook
}

main "$@"
