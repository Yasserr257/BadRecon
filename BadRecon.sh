#!/bin/bash

# ============================================================
#  BADRECON v2.2
#  Automated Recon Pipeline (Passive, Archive, Active, Live)
#  Enhanced with Logging & Stats
# ============================================================

DOMAIN=$1
START_TIME=$(date +%s)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------
#  🔥 BADRECON BANNER 🔥
# -----------------------------------------------------------------------
echo -e "${CYAN}"
echo " ____            _ ____  "
echo "| __ )  __ _  __| |  _ \ ___  ___ ___  _ __  "
echo "|  _ \ / _\` |/ _\` | |_) / _ \/ __/ _ \| '_ \ "
echo "| |_) | (_| | (_| |  _ <  __/ (_| (_) | | | |"
echo "|____/ \__,_|\__,_|_| \_\___|\___\___/|_| |_|"
echo -e "          Recon Automation v2.2             ${NC}"
echo ""

# -----------------------------------------------------------------------
#  VALIDATION
# -----------------------------------------------------------------------
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}[!] Usage: ./BadRecon.sh <domain>${NC}"
    exit 1
fi

# Create Directory & Log (must happen before LOG_FILE is used)
mkdir -p "$DOMAIN"/01_Subdomains
mkdir -p "$DOMAIN"/02_DNS
mkdir -p "$DOMAIN"/03_Network
mkdir -p "$DOMAIN"/04_Live
mkdir -p "$DOMAIN"/logs

LOG_FILE="$DOMAIN/badrecon.log"

# -----------------------------------------------------------------------
#  FUNCTION: Logging
# -----------------------------------------------------------------------
log_message() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="$1"
    local log_type="$2"

    case $log_type in
        "INFO")
            echo -e "${BLUE}[${timestamp}] [i] ${message}${NC}" | tee -a "$LOG_FILE"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[${timestamp}] [+] ${message}${NC}" | tee -a "$LOG_FILE"
            ;;
        "WARNING")
            echo -e "${YELLOW}[${timestamp}] [!] ${message}${NC}" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[${timestamp}] [x] ${message}${NC}" | tee -a "$LOG_FILE"
            ;;
    esac
}

# -----------------------------------------------------------------------
#  FUNCTION: Count Lines
# -----------------------------------------------------------------------
count_results() {
    local file="$1"
    if [ -f "$file" ]; then
        wc -l < "$file" 2>/dev/null | tr -d ' ' || echo "0"
    else
        echo "0"
    fi
}

# -----------------------------------------------------------------------
#  FUNCTION: Timer
# -----------------------------------------------------------------------
get_elapsed_time() {
    local end_time=$(date +%s)
    local elapsed=$((end_time - START_TIME))
    local mins=$((elapsed / 60))
    local secs=$((elapsed % 60))
    printf "%d:%02d" $mins $secs
}

log_message "Starting reconnaissance for: $DOMAIN" "INFO"
log_message "===============================================" "INFO"

# -----------------------------------------------------------------------
#  FUNCTION: Check Dependencies
# -----------------------------------------------------------------------
check_dependencies() {
    local missing=()
    local required_tools=("subfinder" "assetfinder" "puredns" "dnsx" "tlsx" "dig" "python3")

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing+=("$tool")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        log_message "Missing required tools: ${missing[*]}" "ERROR"
        log_message "Please install them before running BadRecon." "ERROR"
        exit 1
    fi

    if ! command -v httpx &> /dev/null && [ ! -f "$LIVE_CHECK_SCRIPT" ]; then
        log_message "Neither httpx nor a custom live-check script found. Phase 6 will be skipped." "WARNING"
    fi
}

# Configuration
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORDLIST="$CURRENT_DIR/subdomains-top1million-110000.txt"
RESOLVERS="$CURRENT_DIR/resolvers.txt"
LIVE_CHECK_SCRIPT="$CURRENT_DIR/thc_livecheck.py"
WAYMORE_SCRIPT="$CURRENT_DIR/waymore/waymore.py"

check_dependencies

# Check Wordlist
if [ ! -f "$WORDLIST" ]; then
    log_message "Wordlist not found at $WORDLIST. Puredns bruteforce will be skipped." "WARNING"
    SKIP_BRUTE=1
fi

# Check Resolvers
if [ ! -f "$RESOLVERS" ]; then
    log_message "Resolvers file not found. Downloading..." "WARNING"
    if wget -q https://raw.githubusercontent.com/trickest/resolvers/main/resolvers.txt -O "$CURRENT_DIR/resolvers.txt"; then
        RESOLVERS="$CURRENT_DIR/resolvers.txt"
        log_message "Resolvers downloaded successfully" "SUCCESS"
    else
        log_message "Failed to download resolvers. DNS resolution steps may fail." "ERROR"
    fi
fi

# ============================================================
# PHASE 1: PASSIVE RECON
# ============================================================
log_message "[1/6] Running Passive Enumeration..." "INFO"
PHASE1_START=$(date +%s)

log_message "  -> Subfinder (APIs)..." "INFO"
subfinder -d "$DOMAIN" -all -silent -o "$DOMAIN/01_Subdomains/subfinder.txt" 2>/dev/null
SUBFINDER_COUNT=$(count_results "$DOMAIN/01_Subdomains/subfinder.txt")
log_message "  -> Subfinder found: $SUBFINDER_COUNT subdomains" "SUCCESS"

log_message "  -> Assetfinder..." "INFO"
assetfinder -subs-only "$DOMAIN" > "$DOMAIN/01_Subdomains/assetfinder.txt" 2>/dev/null
ASSETFINDER_COUNT=$(count_results "$DOMAIN/01_Subdomains/assetfinder.txt")
log_message "  -> Assetfinder found: $ASSETFINDER_COUNT subdomains" "SUCCESS"

PHASE1_END=$(date +%s)
PHASE1_TIME=$((PHASE1_END - PHASE1_START))

# ============================================================
# PHASE 2: ARCHIVE MINING
# ============================================================
log_message "[2/6] Mining Archives (Waymore)..." "INFO"
PHASE2_START=$(date +%s)

WAYMORE_COUNT=0
if [ -f "$WAYMORE_SCRIPT" ]; then
    python3 "$WAYMORE_SCRIPT" -i "$DOMAIN" -mode U -oU "$DOMAIN/01_Subdomains/waymore_urls.txt" > /dev/null 2>&1
    if [ -f "$DOMAIN/01_Subdomains/waymore_urls.txt" ]; then
        cut -d "/" -f3 < "$DOMAIN/01_Subdomains/waymore_urls.txt" | cut -d ":" -f1 | sort -u > "$DOMAIN/01_Subdomains/waymore_subs.txt"
        WAYMORE_COUNT=$(count_results "$DOMAIN/01_Subdomains/waymore_subs.txt")
        log_message "  -> Waymore found: $WAYMORE_COUNT subdomains" "SUCCESS"
    else
        log_message "  -> Waymore output empty" "WARNING"
    fi
else
    log_message "  -> Waymore script not found at $WAYMORE_SCRIPT, skipping" "WARNING"
fi

PHASE2_END=$(date +%s)
PHASE2_TIME=$((PHASE2_END - PHASE2_START))

# ============================================================
# PHASE 3: ACTIVE & NETWORK
# ============================================================
log_message "[3/6] Active Recon & Network Scanning..." "INFO"
PHASE3_START=$(date +%s)

if [ -z "$SKIP_BRUTE" ] && [ -f "$RESOLVERS" ]; then
    log_message "  -> DNS Bruteforce (Puredns)..." "INFO"
    puredns bruteforce "$WORDLIST" "$DOMAIN" -r "$RESOLVERS" -w "$DOMAIN/01_Subdomains/puredns_brute.txt" --rate-limit 100 --threads 20 --quiet 2>/dev/null
    PUREDNS_COUNT=$(count_results "$DOMAIN/01_Subdomains/puredns_brute.txt")
    log_message "  -> Puredns found: $PUREDNS_COUNT subdomains" "SUCCESS"
else
    log_message "  -> Skipping DNS Bruteforce (missing wordlist or resolvers)" "WARNING"
    PUREDNS_COUNT=0
fi

log_message "  -> Zone Transfer Check..." "INFO"
> "$DOMAIN/03_Network/zone_transfer.txt"
NS_SERVERS=$(dig +short ns "$DOMAIN" 2>/dev/null)
if [ -n "$NS_SERVERS" ]; then
    while read -r ns; do
        [ -z "$ns" ] && continue
        dig axfr @"$ns" "$DOMAIN" 2>/dev/null
    done <<< "$NS_SERVERS" | grep -E "^[a-zA-Z0-9]" | awk '{print $1}' | sed 's/\.$//' | sort -u > "$DOMAIN/03_Network/zone_transfer.txt"
fi
ZONE_COUNT=$(count_results "$DOMAIN/03_Network/zone_transfer.txt")
if [ "$ZONE_COUNT" -gt 0 ]; then
    log_message "  -> Zone Transfer successful: $ZONE_COUNT records" "SUCCESS"
else
    log_message "  -> Zone Transfer: No records found (expected)" "INFO"
fi

log_message "  -> TLS/SSL Certificate Grabber..." "INFO"
echo "$DOMAIN" | tlsx -san -cn -silent -resp-only 2>/dev/null | sort -u > "$DOMAIN/01_Subdomains/tls_subs.txt"
TLS_COUNT=$(count_results "$DOMAIN/01_Subdomains/tls_subs.txt")
log_message "  -> TLS found: $TLS_COUNT certificates/subdomains" "SUCCESS"

PHASE3_END=$(date +%s)
PHASE3_TIME=$((PHASE3_END - PHASE3_START))

# ============================================================
# PHASE 4: MERGING & DEDUPLICATION
# ============================================================
log_message "[4/6] Merging & Deduplicating..." "INFO"
PHASE4_START=$(date +%s)

cat "$DOMAIN/01_Subdomains/subfinder.txt" \
    "$DOMAIN/01_Subdomains/assetfinder.txt" \
    "$DOMAIN/01_Subdomains/waymore_subs.txt" \
    "$DOMAIN/01_Subdomains/puredns_brute.txt" \
    "$DOMAIN/01_Subdomains/tls_subs.txt" 2>/dev/null | sort -u > "$DOMAIN/all_subs_raw.txt"

RAW_COUNT=$(count_results "$DOMAIN/all_subs_raw.txt")
log_message "  -> Raw Subdomains (before dedup): $RAW_COUNT" "INFO"

RESOLVED_COUNT=0
if [ -f "$RESOLVERS" ] && [ "$RAW_COUNT" -gt 0 ]; then
    log_message "  -> Validating & Resolving Subdomains..." "INFO"
    puredns resolve "$DOMAIN/all_subs_raw.txt" -r "$RESOLVERS" -w "$DOMAIN/02_DNS/resolved_subs.txt" --rate-limit 100 --threads 20 --quiet 2>/dev/null
    RESOLVED_COUNT=$(count_results "$DOMAIN/02_DNS/resolved_subs.txt")
    log_message "  -> Live Subdomains (resolved): $RESOLVED_COUNT" "SUCCESS"
else
    log_message "  -> Skipping resolution (no resolvers or no raw subdomains)" "WARNING"
    touch "$DOMAIN/02_DNS/resolved_subs.txt"
fi

PHASE4_END=$(date +%s)
PHASE4_TIME=$((PHASE4_END - PHASE4_START))

# ============================================================
# PHASE 5: IP EXTRACTION
# ============================================================
log_message "[5/6] Extracting IPs for Pivot..." "INFO"
PHASE5_START=$(date +%s)

dnsx -l "$DOMAIN/02_DNS/resolved_subs.txt" -a -resp-only -silent 2>/dev/null | sort -u > "$DOMAIN/03_Network/public_ips.txt"
IP_COUNT=$(count_results "$DOMAIN/03_Network/public_ips.txt")
log_message "  -> Unique IP Addresses: $IP_COUNT" "SUCCESS"

dnsx -l "$DOMAIN/03_Network/public_ips.txt" -ptr -resp-only -silent 2>/dev/null > "$DOMAIN/03_Network/ptr_records.txt"
PTR_COUNT=$(count_results "$DOMAIN/03_Network/ptr_records.txt")
log_message "  -> PTR Records: $PTR_COUNT" "SUCCESS"

PHASE5_END=$(date +%s)
PHASE5_TIME=$((PHASE5_END - PHASE5_START))

# ============================================================
# PHASE 6: LIVE CHECK
# ============================================================
log_message "[6/6] Final Live Check & Sorting..." "INFO"
PHASE6_START=$(date +%s)

if [ -f "$LIVE_CHECK_SCRIPT" ]; then
    python3 "$LIVE_CHECK_SCRIPT" -i "$DOMAIN/02_DNS/resolved_subs.txt" -o "$DOMAIN/04_Live/live_report.txt" --screenshots 2>/dev/null
    log_message "  -> Live check completed with screenshots" "SUCCESS"
elif command -v httpx &> /dev/null; then
    log_message "  -> Custom script not found. Using fallback (httpx)..." "WARNING"
    httpx -l "$DOMAIN/02_DNS/resolved_subs.txt" -silent -sc -title -o "$DOMAIN/04_Live/fallback_live.txt" 2>/dev/null
    log_message "  -> Fallback live check completed" "SUCCESS"
else
    log_message "  -> No live-check tool available. Skipping Phase 6." "WARNING"
fi

LIVE_COUNT=$(count_results "$DOMAIN/04_Live/live_report.txt")
if [ "$LIVE_COUNT" -eq 0 ]; then
    LIVE_COUNT=$(count_results "$DOMAIN/04_Live/fallback_live.txt")
fi

PHASE6_END=$(date +%s)
PHASE6_TIME=$((PHASE6_END - PHASE6_START))

# ============================================================
# FINAL SUMMARY & STATS
# ============================================================
TOTAL_END=$(date +%s)
TOTAL_TIME=$((TOTAL_END - START_TIME))
TOTAL_MINS=$((TOTAL_TIME / 60))
TOTAL_SECS=$((TOTAL_TIME % 60))

log_message "===============================================" "INFO"

# Summary Report
SUMMARY_FILE="$DOMAIN/SUMMARY_REPORT.txt"
cat > "$SUMMARY_FILE" << EOF
==========================================================
          BADRECON SCAN SUMMARY REPORT
          Domain: $DOMAIN
==========================================================

RESULTS BY SOURCE:
----------------------------------------------------------
 Subfinder           : $SUBFINDER_COUNT subdomains
 Assetfinder         : $ASSETFINDER_COUNT subdomains
 Puredns Bruteforce  : $PUREDNS_COUNT subdomains
 Waymore (Archive)   : $WAYMORE_COUNT subdomains
 TLS Certificates    : $TLS_COUNT subdomains
 Zone Transfer       : $ZONE_COUNT records

AGGREGATED STATS:
----------------------------------------------------------
 Total Raw (before dedup)  : $RAW_COUNT subdomains
 Live & Resolved           : $RESOLVED_COUNT subdomains
 Unique IP Addresses       : $IP_COUNT IPs
 PTR Records               : $PTR_COUNT records

LIVE WEB SERVERS:
----------------------------------------------------------
 Live Web Servers Found    : $LIVE_COUNT

EXECUTION TIME BY PHASE:
----------------------------------------------------------
 Phase 1 (Passive)         : ${PHASE1_TIME}s
 Phase 2 (Archive Mining)  : ${PHASE2_TIME}s
 Phase 3 (Active Recon)    : ${PHASE3_TIME}s
 Phase 4 (Merging)         : ${PHASE4_TIME}s
 Phase 5 (IP Extraction)   : ${PHASE5_TIME}s
 Phase 6 (Live Check)      : ${PHASE6_TIME}s
 --------------------------
 TOTAL TIME                : ${TOTAL_MINS}m ${TOTAL_SECS}s

OUTPUT LOCATIONS:
----------------------------------------------------------
 Resolved Subdomains : $DOMAIN/02_DNS/resolved_subs.txt
 IP Addresses        : $DOMAIN/03_Network/public_ips.txt
 PTR Records         : $DOMAIN/03_Network/ptr_records.txt
 Live Results        : $DOMAIN/04_Live/
 Full Log            : $DOMAIN/badrecon.log

==========================================================
 Scan completed in ${TOTAL_MINS}m ${TOTAL_SECS}s
==========================================================
EOF

cat "$SUMMARY_FILE" | tee -a "$LOG_FILE"

log_message "Summary report saved to: $SUMMARY_FILE" "SUCCESS"
log_message "Full log saved to: $LOG_FILE" "SUCCESS"
log_message "===============================================" "INFO"
