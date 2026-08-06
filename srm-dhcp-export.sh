#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2026 Nicolas Lermé <nicolas.lerme@gmail.com>
# SPDX-License-Identifier: LGPL-3.0-only
#
# srm-dhcp-export
# Export Synology SRM DHCP reservations over SSH and generate CSV/PDF reports.

set -Eeuo pipefail
umask 077

readonly PROJECT_NAME="srm-dhcp-export"
readonly VERSION="1.0.1"
readonly TOTAL_STEPS=8
readonly DEFAULT_HOST="192.168.1.1"
readonly DEFAULT_PORT="22"
readonly DEFAULT_USER="root"
readonly DEFAULT_OUTPUT="device_list.pdf"
readonly REMOTE_CONFIG="/etc/dhcpd/dhcpd.conf"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly DEFAULT_CSS="${SCRIPT_DIR}/styles/report.css"
readonly PROCESSOR="${SCRIPT_DIR}/lib/process_reservations.py"
readonly PDF_RENDERER="${SCRIPT_DIR}/lib/render_pdf.py"
readonly HTML_TEMPLATE="${SCRIPT_DIR}/templates/report.html"

NON_INTERACTIVE=0
AUTO_INSTALL=0
FORCE=0
KEEP_HTML=0
SSH_HOST=""
SSH_PORT=""
SSH_USER=""
OUTPUT_INPUT=""
CSS_INPUT=""

WORK_DIR=""
CONTROL_SOCKET=""
REMOTE_FILE=""
SSH_DESTINATION=""
SCP_DESTINATION=""
REMOTE_FILE_CREATED=0
SSH_MASTER_STARTED=0

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    readonly C_RED=$'\033[31m'
    readonly C_GREEN=$'\033[32m'
    readonly C_YELLOW=$'\033[33m'
    readonly C_BLUE=$'\033[34m'
    readonly C_CYAN=$'\033[36m'
    readonly C_BOLD=$'\033[1m'
    readonly C_DIM=$'\033[2m'
    readonly C_RESET=$'\033[0m'
else
    readonly C_RED=""
    readonly C_GREEN=""
    readonly C_YELLOW=""
    readonly C_BLUE=""
    readonly C_CYAN=""
    readonly C_BOLD=""
    readonly C_DIM=""
    readonly C_RESET=""
fi

usage() {
    cat <<USAGE
${PROJECT_NAME} ${VERSION}

Usage:
  ./srm-dhcp-export.sh [options]

Options:
  --host HOST              Router IP address or DNS name.
  --port PORT              SSH port (default: ${DEFAULT_PORT}).
  --user USER              SSH user (default: ${DEFAULT_USER}).
  --output FILE            Output PDF path (default: ${DEFAULT_OUTPUT}).
  --css FILE               Custom PDF stylesheet.
  --keep-html              Keep the generated HTML file beside the PDF.
  --force                  Overwrite existing output files without asking.
  --non-interactive        Use supplied values/defaults without prompts.
  --install-dependencies   Install missing dependencies without confirmation.
  --check-dependencies     Check dependencies and exit.
  --version                Print the version and exit.
  -h, --help               Show this help message.

Examples:
  ./srm-dhcp-export.sh
  ./srm-dhcp-export.sh --host 192.168.1.1 --output reports/devices.pdf
  ./srm-dhcp-export.sh --css styles/report.css --keep-html
USAGE
}

print_banner() {
    printf '\n%b%s%b\n' "${C_BOLD}${C_CYAN}" "${PROJECT_NAME} ${VERSION}" "${C_RESET}"
    printf '%b%s%b\n\n' "${C_DIM}" "Synology SRM DHCP reservation exporter" "${C_RESET}"
}

print_step() {
    local number="$1"
    local title="$2"
    printf '\n%b[%d/%d]%b %b%s%b\n' \
        "${C_BOLD}${C_BLUE}" "$number" "$TOTAL_STEPS" "${C_RESET}" \
        "${C_BOLD}" "$title" "${C_RESET}"
}

print_ok() {
    printf '  %b[OK]%b %s\n' "${C_GREEN}${C_BOLD}" "${C_RESET}" "$1"
}

print_info() {
    printf '  %b[INFO]%b %s\n' "${C_CYAN}${C_BOLD}" "${C_RESET}" "$1"
}

print_warning() {
    printf '  %b[WARN]%b %s\n' "${C_YELLOW}${C_BOLD}" "${C_RESET}" "$1" >&2
}

print_error() {
    printf '\n%b[ERROR]%b %s\n' "${C_RED}${C_BOLD}" "${C_RESET}" "$1" >&2
}

abort() {
    print_error "$1"
    exit "${2:-1}"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

trim_whitespace() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

prompt_with_default() {
    local prompt_text="$1"
    local default_value="$2"
    local response=""

    printf '  %b%s%b [%s]: ' "${C_BOLD}" "$prompt_text" "${C_RESET}" "$default_value" >&2
    if ! IFS= read -r response; then
        abort "Input was interrupted."
    fi

    response="$(trim_whitespace "$response")"
    if [[ -z "$response" ]]; then
        response="$default_value"
    fi

    printf '%s' "$response"
}

prompt_yes_no() {
    local prompt_text="$1"
    local default_answer="${2:-no}"
    local answer=""

    while true; do
        if [[ "$default_answer" == "yes" ]]; then
            printf '  %s [Y/n]: ' "$prompt_text" >&2
        else
            printf '  %s [y/N]: ' "$prompt_text" >&2
        fi

        if ! IFS= read -r answer; then
            abort "Input was interrupted."
        fi
        answer="$(trim_whitespace "$answer")"

        if [[ -z "$answer" ]]; then
            [[ "$default_answer" == "yes" ]]
            return
        fi

        case "$answer" in
            y|Y|yes|Yes|YES) return 0 ;;
            n|N|no|No|NO) return 1 ;;
            *) print_warning "Invalid answer. Enter yes or no." ;;
        esac
    done
}

validate_host() {
    local host="$1"
    [[ -n "$host" ]] || return 1
    [[ "$host" != -* ]] || return 1
    [[ "$host" != *'@'* ]] || return 1
    [[ "$host" != *'/'* ]] || return 1
    [[ "$host" != *' '* ]] || return 1
    [[ "$host" != *$'\n'* ]] || return 1
    [[ "$host" =~ ^[A-Za-z0-9._:-]+$ ]]
}

validate_user() {
    local user_name="$1"
    [[ "$user_name" =~ ^[A-Za-z0-9._-]+$ ]]
}

validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    (( port >= 1 && port <= 65535 ))
}

normalize_pdf_name() {
    local path="$1"
    local suffix="${path##*.}"
    case "$suffix" in
        pdf|PDF|Pdf|pDf|pdF|PDf|pDF) printf '%s' "$path" ;;
        *) printf '%s.pdf' "$path" ;;
    esac
}

get_absolute_path() {
    python3 - "$1" <<'PY'
import os
import sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
}

MISSING_COMPONENTS=()
INSTALL_PACKAGES=()

collect_missing_dependencies() {
    MISSING_COMPONENTS=()

    if ! command_exists ssh || ! command_exists scp; then
        MISSING_COMPONENTS+=("OpenSSH client (ssh/scp)")
    fi
    if ! command_exists python3; then
        MISSING_COMPONENTS+=("Python 3")
        MISSING_COMPONENTS+=("WeasyPrint Python package")
    elif ! python3 -c 'import weasyprint' >/dev/null 2>&1; then
        MISSING_COMPONENTS+=("WeasyPrint Python package")
    fi
    if ! command_exists mktemp; then
        MISSING_COMPONENTS+=("mktemp/core utilities")
    fi
}

print_missing_dependencies() {
    local item
    print_warning "Missing dependencies:"
    for item in "${MISSING_COMPONENTS[@]}"; do
        printf '    - %s\n' "$item" >&2
    done
}

detect_package_manager() {
    local manager
    for manager in apt-get dnf yum pacman zypper apk brew; do
        if command_exists "$manager"; then
            printf '%s' "$manager"
            return 0
        fi
    done
    return 1
}

add_package() {
    local package="$1"
    local existing
    for existing in "${INSTALL_PACKAGES[@]}"; do
        [[ "$existing" == "$package" ]] && return 0
    done
    INSTALL_PACKAGES+=("$package")
}

build_package_list() {
    local manager="$1"
    local component
    INSTALL_PACKAGES=()

    for component in "${MISSING_COMPONENTS[@]}"; do
        case "$manager:$component" in
            apt-get:'OpenSSH client (ssh/scp)') add_package openssh-client ;;
            apt-get:'Python 3') add_package python3 ;;
            apt-get:'WeasyPrint Python package') add_package weasyprint ;;
            apt-get:'mktemp/core utilities') add_package coreutils ;;

            dnf:'OpenSSH client (ssh/scp)'|yum:'OpenSSH client (ssh/scp)') add_package openssh-clients ;;
            dnf:'Python 3'|yum:'Python 3') add_package python3 ;;
            dnf:'WeasyPrint Python package'|yum:'WeasyPrint Python package') add_package weasyprint ;;
            dnf:'mktemp/core utilities'|yum:'mktemp/core utilities') add_package coreutils ;;

            pacman:'OpenSSH client (ssh/scp)') add_package openssh ;;
            pacman:'Python 3') add_package python ;;
            pacman:'WeasyPrint Python package') add_package python-weasyprint ;;
            pacman:'mktemp/core utilities') add_package coreutils ;;

            zypper:'OpenSSH client (ssh/scp)') add_package openssh ;;
            zypper:'Python 3') add_package python3 ;;
            zypper:'WeasyPrint Python package') add_package python3-WeasyPrint ;;
            zypper:'mktemp/core utilities') add_package coreutils ;;

            apk:'OpenSSH client (ssh/scp)') add_package openssh-client ;;
            apk:'Python 3') add_package python3 ;;
            apk:'WeasyPrint Python package') add_package py3-weasyprint ;;
            apk:'mktemp/core utilities') add_package coreutils ;;

            brew:'OpenSSH client (ssh/scp)') add_package openssh ;;
            brew:'Python 3') add_package python ;;
            brew:'WeasyPrint Python package') add_package weasyprint ;;
            brew:'mktemp/core utilities') add_package coreutils ;;
        esac
    done
}

print_install_command() {
    local manager="$1"
    local prefix=""
    [[ "$manager" != "brew" && "${EUID:-$(id -u)}" -ne 0 ]] && prefix="sudo "

    case "$manager" in
        apt-get)
            printf '%sapt-get update && %sapt-get install -y' "$prefix" "$prefix"
            ;;
        dnf|yum)
            printf '%s%s install -y' "$prefix" "$manager"
            ;;
        pacman)
            printf '%spacman -Sy --needed' "$prefix"
            ;;
        zypper)
            printf '%szypper --non-interactive install' "$prefix"
            ;;
        apk)
            printf '%sapk add' "$prefix"
            ;;
        brew)
            printf 'brew install'
            ;;
    esac
    printf ' %s' "${INSTALL_PACKAGES[@]}"
}

run_as_root() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        "$@"
    elif command_exists sudo; then
        sudo "$@"
    else
        print_error "sudo is required to install system packages."
        return 1
    fi
}

install_missing_dependencies() {
    local manager="$1"
    build_package_list "$manager"

    if [[ "${#INSTALL_PACKAGES[@]}" -eq 0 ]]; then
        return 1
    fi

    print_info "Proposed installation command:"
    printf '    %b' "${C_BOLD}"
    print_install_command "$manager"
    printf '%b\n' "${C_RESET}"

    if [[ "$AUTO_INSTALL" -ne 1 ]]; then
        if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
            return 1
        fi
        prompt_yes_no "Install the missing dependencies now?" "no" || return 1
    fi

    case "$manager" in
        apt-get)
            run_as_root apt-get update
            run_as_root apt-get install -y "${INSTALL_PACKAGES[@]}"
            ;;
        dnf|yum)
            run_as_root "$manager" install -y "${INSTALL_PACKAGES[@]}"
            ;;
        pacman)
            run_as_root pacman -Sy --needed "${INSTALL_PACKAGES[@]}"
            ;;
        zypper)
            run_as_root zypper --non-interactive install "${INSTALL_PACKAGES[@]}"
            ;;
        apk)
            run_as_root apk add "${INSTALL_PACKAGES[@]}"
            ;;
        brew)
            brew install "${INSTALL_PACKAGES[@]}"
            ;;
        *)
            return 1
            ;;
    esac

    hash -r
}

check_project_files() {
    local file
    for file in "$PROCESSOR" "$PDF_RENDERER" "$HTML_TEMPLATE" "$DEFAULT_CSS"; do
        [[ -r "$file" ]] || abort "Required bundle file is missing or unreadable: $file"
    done
}

cleanup() {
    local exit_status=$?
    trap - EXIT

    if [[ "$REMOTE_FILE_CREATED" -eq 1 && -n "$SSH_DESTINATION" && -n "$REMOTE_FILE" && -n "$CONTROL_SOCKET" ]]; then
        ssh -S "$CONTROL_SOCKET" -p "${SSH_PORT:-22}" \
            -o ConnectTimeout=5 -o LogLevel=ERROR \
            "$SSH_DESTINATION" "rm -f '$REMOTE_FILE'" \
            >/dev/null 2>&1 || true
    fi

    if [[ "$SSH_MASTER_STARTED" -eq 1 && -n "$CONTROL_SOCKET" && -n "$SSH_DESTINATION" ]]; then
        ssh -S "$CONTROL_SOCKET" -O exit -p "${SSH_PORT:-22}" \
            "$SSH_DESTINATION" >/dev/null 2>&1 || true
    fi

    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi

    exit "$exit_status"
}

CHECK_ONLY=0
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --host)
            [[ "$#" -ge 2 ]] || abort "--host requires a value."
            SSH_HOST="$2"
            shift 2
            ;;
        --port)
            [[ "$#" -ge 2 ]] || abort "--port requires a value."
            SSH_PORT="$2"
            shift 2
            ;;
        --user)
            [[ "$#" -ge 2 ]] || abort "--user requires a value."
            SSH_USER="$2"
            shift 2
            ;;
        --output)
            [[ "$#" -ge 2 ]] || abort "--output requires a value."
            OUTPUT_INPUT="$2"
            shift 2
            ;;
        --css)
            [[ "$#" -ge 2 ]] || abort "--css requires a value."
            CSS_INPUT="$2"
            shift 2
            ;;
        --keep-html)
            KEEP_HTML=1
            shift
            ;;
        --force)
            FORCE=1
            shift
            ;;
        --non-interactive)
            NON_INTERACTIVE=1
            shift
            ;;
        --install-dependencies)
            AUTO_INSTALL=1
            shift
            ;;
        --check-dependencies)
            CHECK_ONLY=1
            shift
            ;;
        --version)
            printf '%s %s\n' "$PROJECT_NAME" "$VERSION"
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            abort "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

trap cleanup EXIT
trap 'exit 130' INT TERM HUP

print_banner
check_project_files

print_step 1 "Checking local dependencies"
collect_missing_dependencies
if [[ "${#MISSING_COMPONENTS[@]}" -gt 0 ]]; then
    print_missing_dependencies
    PACKAGE_MANAGER="$(detect_package_manager || true)"
    if [[ -n "$PACKAGE_MANAGER" ]]; then
        if ! install_missing_dependencies "$PACKAGE_MANAGER"; then
            abort "Dependencies were not installed. Install them manually and run the script again."
        fi
        collect_missing_dependencies
    else
        abort "No supported package manager was found. Install OpenSSH, Python 3, WeasyPrint, and core utilities manually."
    fi
fi

if [[ "${#MISSING_COMPONENTS[@]}" -gt 0 ]]; then
    print_missing_dependencies
    abort "Some dependencies are still unavailable after installation."
fi

PYTHON_VERSION="$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')"
if ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 8) else 1)'; then
    abort "Python 3.8 or later is required; found Python ${PYTHON_VERSION}."
fi
WEASYPRINT_VERSION="$(python3 -c 'import weasyprint; print(weasyprint.__version__)')"
print_ok "OpenSSH, Python ${PYTHON_VERSION}, WeasyPrint ${WEASYPRINT_VERSION}, and core utilities are available."

if [[ "$CHECK_ONLY" -eq 1 ]]; then
    printf '\n%bDependency check completed successfully.%b\n' "${C_GREEN}${C_BOLD}" "${C_RESET}"
    exit 0
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sde.XXXXXX")" || abort "Unable to create a local temporary directory."
CONTROL_SOCKET="${WORK_DIR}/ssh.sock"
RAW_FILE="${WORK_DIR}/reservations.raw"
TEMP_CSV="${WORK_DIR}/reservations.csv"
TEMP_HTML="${WORK_DIR}/reservations.html"
TEMP_PDF="${WORK_DIR}/reservations.pdf"
REMOTE_FILE="/tmp/srm_dhcp_export_${$}_${RANDOM}.txt"

print_step 2 "Collecting and validating settings"

SSH_HOST="${SSH_HOST:-$DEFAULT_HOST}"
SSH_PORT="${SSH_PORT:-$DEFAULT_PORT}"
SSH_USER="${SSH_USER:-$DEFAULT_USER}"
OUTPUT_INPUT="${OUTPUT_INPUT:-$DEFAULT_OUTPUT}"
CSS_INPUT="${CSS_INPUT:-$DEFAULT_CSS}"

if [[ "$NON_INTERACTIVE" -ne 1 ]]; then
    while true; do
        SSH_HOST="$(prompt_with_default "Router IP address or host name" "$SSH_HOST")"
        validate_host "$SSH_HOST" && break
        print_warning "Invalid host. Use an IPv4/IPv6 address or DNS name without spaces, slashes, or @ characters."
    done

    while true; do
        SSH_PORT="$(prompt_with_default "SSH port" "$SSH_PORT")"
        validate_port "$SSH_PORT" && break
        print_warning "Invalid port. Enter a number from 1 to 65535."
    done

    while true; do
        SSH_USER="$(prompt_with_default "SSH user" "$SSH_USER")"
        validate_user "$SSH_USER" && break
        print_warning "Invalid user name. Use letters, numbers, dots, hyphens, or underscores only."
    done

    while true; do
        OUTPUT_INPUT="$(prompt_with_default "Output PDF file" "$OUTPUT_INPUT")"
        OUTPUT_INPUT="$(normalize_pdf_name "$OUTPUT_INPUT")"
        [[ "$OUTPUT_INPUT" != *$'\n'* ]] && break
        print_warning "The output path must not contain line breaks."
    done
else
    validate_host "$SSH_HOST" || abort "Invalid --host value."
    validate_port "$SSH_PORT" || abort "Invalid --port value."
    validate_user "$SSH_USER" || abort "Invalid --user value."
    OUTPUT_INPUT="$(normalize_pdf_name "$OUTPUT_INPUT")"
fi

OUTPUT_PDF="$(get_absolute_path "$OUTPUT_INPUT")" || abort "Unable to resolve the output path."
CSS_FILE="$(get_absolute_path "$CSS_INPUT")" || abort "Unable to resolve the CSS path."
OUTPUT_DIR="${OUTPUT_PDF%/*}"
[[ -n "$OUTPUT_DIR" ]] || OUTPUT_DIR="/"
OUTPUT_NAME="${OUTPUT_PDF##*/}"
OUTPUT_STEM="${OUTPUT_NAME%.*}"
OUTPUT_CSV="${OUTPUT_DIR}/${OUTPUT_STEM}.csv"
OUTPUT_HTML="${OUTPUT_DIR}/${OUTPUT_STEM}.html"

[[ -n "$OUTPUT_STEM" && "$OUTPUT_STEM" != "." && "$OUTPUT_STEM" != ".." ]] || abort "Invalid output file name."
[[ -d "$OUTPUT_DIR" ]] || abort "The output directory does not exist: $OUTPUT_DIR"
[[ -w "$OUTPUT_DIR" ]] || abort "The output directory is not writable: $OUTPUT_DIR"
[[ -r "$CSS_FILE" ]] || abort "The CSS file is not readable: $CSS_FILE"

EXISTING_OUTPUTS=()
[[ -e "$OUTPUT_PDF" ]] && EXISTING_OUTPUTS+=("$OUTPUT_PDF")
[[ -e "$OUTPUT_CSV" ]] && EXISTING_OUTPUTS+=("$OUTPUT_CSV")
[[ "$KEEP_HTML" -eq 1 && -e "$OUTPUT_HTML" ]] && EXISTING_OUTPUTS+=("$OUTPUT_HTML")

if [[ "${#EXISTING_OUTPUTS[@]}" -gt 0 && "$FORCE" -ne 1 ]]; then
    print_warning "One or more output files already exist:"
    for existing in "${EXISTING_OUTPUTS[@]}"; do
        printf '    - %s\n' "$existing" >&2
    done
    if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
        abort "Use --force to overwrite existing files in non-interactive mode."
    fi
    prompt_yes_no "Overwrite the existing output files?" "no" || abort "Export cancelled by the user." 2
fi

SSH_DESTINATION="${SSH_USER}@${SSH_HOST}"
if [[ "$SSH_HOST" == *:* ]]; then
    SCP_DESTINATION="${SSH_USER}@[${SSH_HOST}]"
else
    SCP_DESTINATION="$SSH_DESTINATION"
fi

print_info "SSH target : ${SSH_DESTINATION}:${SSH_PORT}"
print_info "PDF output : ${OUTPUT_PDF}"
print_info "CSV output : ${OUTPUT_CSV}"
[[ "$KEEP_HTML" -eq 1 ]] && print_info "HTML output: ${OUTPUT_HTML}"
print_info "Stylesheet : ${CSS_FILE}"
print_info "Any password prompt is handled directly by OpenSSH."

print_step 3 "Opening the SSH connection"
SSH_COMMON_OPTIONS=(
    -S "$CONTROL_SOCKET"
    -p "$SSH_PORT"
    -o ConnectTimeout=15
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=2
    -o LogLevel=ERROR
)

if ! ssh -M -o ControlMaster=yes -o ControlPersist=120 "${SSH_COMMON_OPTIONS[@]}" \
    "$SSH_DESTINATION" "printf 'SSH connection established.\\n'"; then
    abort "SSH authentication failed. Check the host, port, user, password/key, account status, and SRM SSH settings."
fi
SSH_MASTER_STARTED=1
print_ok "The SSH connection is open and will be reused for this export."

print_step 4 "Creating the reservation list on the router"
REMOTE_EXPORT_COMMAND="set -eu; umask 077; if [ ! -r '$REMOTE_CONFIG' ]; then printf '%s\\n' 'DHCP configuration is not readable: $REMOTE_CONFIG' >&2; exit 41; fi; grep '^[[:space:]]*dhcp-host=' '$REMOTE_CONFIG' > '$REMOTE_FILE' || true; if [ ! -s '$REMOTE_FILE' ]; then rm -f '$REMOTE_FILE'; printf '%s\\n' 'No DHCP reservations were found.' >&2; exit 42; fi; chmod 600 '$REMOTE_FILE'"

if ! ssh "${SSH_COMMON_OPTIONS[@]}" "$SSH_DESTINATION" "$REMOTE_EXPORT_COMMAND"; then
    abort "Unable to create the remote list. Verify access to ${REMOTE_CONFIG} and confirm that DHCP reservations exist."
fi
REMOTE_FILE_CREATED=1
print_ok "A protected temporary list was created on the router."

print_step 5 "Downloading the reservation list"
if ! scp -P "$SSH_PORT" \
    -o "ControlPath=${CONTROL_SOCKET}" \
    -o ConnectTimeout=15 \
    -o LogLevel=ERROR \
    "${SCP_DESTINATION}:${REMOTE_FILE}" "$RAW_FILE"; then
    abort "The SCP download failed."
fi

[[ -s "$RAW_FILE" ]] || abort "The downloaded reservation list is empty."
RAW_COUNT="$(wc -l < "$RAW_FILE" | tr -d '[:space:]')"
print_ok "Downloaded ${RAW_COUNT} raw reservation line(s)."

print_step 6 "Normalizing data and creating the CSV/HTML reports"
if ! FORMAT_RESULT="$(python3 "$PROCESSOR" \
    --input "$RAW_FILE" \
    --csv "$TEMP_CSV" \
    --html "$TEMP_HTML" \
    --template "$HTML_TEMPLATE" \
    --css "$CSS_FILE" \
    --source "$SSH_HOST" \
    --version "$VERSION")"; then
    abort "The downloaded list could not be parsed or formatted."
fi

IFS='|' read -r FORMATTED_COUNT INCOMPLETE_COUNT INVALID_COUNT DUPLICATE_COUNT <<STATS
$FORMAT_RESULT
STATS

[[ -s "$TEMP_CSV" ]] || abort "The CSV report was not generated."
[[ -s "$TEMP_HTML" ]] || abort "The HTML report was not generated."
print_ok "Created formatted CSV and HTML data for ${FORMATTED_COUNT} device(s)."
[[ "$INCOMPLETE_COUNT" -gt 0 ]] && print_warning "${INCOMPLETE_COUNT} reservation(s) contain at least one missing field."
[[ "$INVALID_COUNT" -gt 0 ]] && print_warning "${INVALID_COUNT} unrecognized line(s) were ignored."
[[ "$DUPLICATE_COUNT" -gt 0 ]] && print_warning "${DUPLICATE_COUNT} exact duplicate(s) were removed."

print_step 7 "Rendering the PDF with the selected CSS"
if ! python3 "$PDF_RENDERER" \
    --html "$TEMP_HTML" \
    --css "$CSS_FILE" \
    --output "$TEMP_PDF"; then
    abort "PDF rendering failed. Run --check-dependencies and review the CSS file."
fi

[[ -s "$TEMP_PDF" ]] || abort "The PDF renderer produced an empty file."
if [[ "$(LC_ALL=C head -c 5 "$TEMP_PDF" 2>/dev/null || true)" != "%PDF-" ]]; then
    abort "The generated file is not a valid PDF."
fi
print_ok "The PDF report was rendered successfully."

print_step 8 "Saving reports and cleaning temporary data"
mv -f "$TEMP_CSV" "$OUTPUT_CSV" || abort "Unable to save the CSV report."
mv -f "$TEMP_PDF" "$OUTPUT_PDF" || abort "Unable to save the PDF report."
if [[ "$KEEP_HTML" -eq 1 ]]; then
    mv -f "$TEMP_HTML" "$OUTPUT_HTML" || abort "Unable to save the HTML report."
fi

chmod 600 "$OUTPUT_CSV" "$OUTPUT_PDF" 2>/dev/null || true
[[ "$KEEP_HTML" -eq 1 ]] && chmod 600 "$OUTPUT_HTML" 2>/dev/null || true

print_ok "Reports were saved with owner-only permissions where supported."
printf '\n%bExport completed successfully.%b\n' "${C_GREEN}${C_BOLD}" "${C_RESET}"
printf '  Devices : %s\n' "$FORMATTED_COUNT"
printf '  PDF     : %s\n' "$OUTPUT_PDF"
printf '  CSV     : %s\n' "$OUTPUT_CSV"
[[ "$KEEP_HTML" -eq 1 ]] && printf '  HTML    : %s\n' "$OUTPUT_HTML"
printf '\n'
