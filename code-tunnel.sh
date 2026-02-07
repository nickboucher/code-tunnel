#!/usr/bin/env bash
# code-tunnel — Launch a VS Code tunnel inside a SLURM interactive GPU job
# https://github.com/nickboucher/code-tunnel
set -euo pipefail

###############################################################################
# Configuration — override any of these with environment variables
###############################################################################
# Required SLURM settings (must be set by user or in env)
CODE_TUNNEL_ACCOUNT="${CODE_TUNNEL_ACCOUNT:-}"
CODE_TUNNEL_PARTITION="${CODE_TUNNEL_PARTITION:-}"

# Optional SLURM settings (sensible defaults)
CODE_TUNNEL_CPUS="${CODE_TUNNEL_CPUS:-2}"
CODE_TUNNEL_GPUS="${CODE_TUNNEL_GPUS:-gpu:1}"
CODE_TUNNEL_MEM="${CODE_TUNNEL_MEM:-}"
CODE_TUNNEL_QOS="${CODE_TUNNEL_QOS:-}"
CODE_TUNNEL_NODES="${CODE_TUNNEL_NODES:-1}"
CODE_TUNNEL_NTASKS="${CODE_TUNNEL_NTASKS:-1}"
CODE_TUNNEL_EXTRA_ARGS="${CODE_TUNNEL_EXTRA_ARGS:-}"
CODE_TUNNEL_SESSION="${CODE_TUNNEL_SESSION:-vscode-tunnel}"

###############################################################################
# Helpers
###############################################################################
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [MINUTES]

Launch a VS Code tunnel inside a SLURM interactive GPU job.

Options:
  -a, --account ACCOUNT     SLURM account (or set CODE_TUNNEL_ACCOUNT)
  -p, --partition PARTITION SLURM partition (or set CODE_TUNNEL_PARTITION)
  -c, --cpus N              CPUs per task        (default: $CODE_TUNNEL_CPUS)
  -g, --gpus GRES           GPU resource spec    (default: $CODE_TUNNEL_GPUS)
  -m, --mem MEM             Memory (e.g. 16G)    (default: SLURM default)
  -q, --qos QOS             Quality of service   (default: none)
      --nodes N             Number of nodes       (default: $CODE_TUNNEL_NODES)
      --ntasks N            Number of tasks       (default: $CODE_TUNNEL_NTASKS)
      --session NAME        Screen session name   (default: $CODE_TUNNEL_SESSION)
      --extra "ARGS"        Additional srun args
  -h, --help                Show this help message

Environment variables:
  CODE_TUNNEL_ACCOUNT, CODE_TUNNEL_PARTITION, CODE_TUNNEL_CPUS,
  CODE_TUNNEL_GPUS, CODE_TUNNEL_MEM, CODE_TUNNEL_QOS, CODE_TUNNEL_NODES,
  CODE_TUNNEL_NTASKS, CODE_TUNNEL_EXTRA_ARGS, CODE_TUNNEL_SESSION

Any option set via a flag takes precedence over the corresponding
environment variable.

Examples:
  $(basename "$0") 60
  $(basename "$0") -a myaccount -p gpu -q high 120
  CODE_TUNNEL_ACCOUNT=myacct $(basename "$0") 90
EOF
    exit 0
}

die() { echo "Error: $*" >&2; exit 1; }

###############################################################################
# Parse command-line arguments
###############################################################################
MINUTES=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--account)    CODE_TUNNEL_ACCOUNT="$2";   shift 2 ;;
        -p|--partition)  CODE_TUNNEL_PARTITION="$2";  shift 2 ;;
        -c|--cpus)       CODE_TUNNEL_CPUS="$2";      shift 2 ;;
        -g|--gpus)       CODE_TUNNEL_GPUS="$2";      shift 2 ;;
        -m|--mem)        CODE_TUNNEL_MEM="$2";        shift 2 ;;
        -q|--qos)        CODE_TUNNEL_QOS="$2";        shift 2 ;;
        --nodes)         CODE_TUNNEL_NODES="$2";      shift 2 ;;
        --ntasks)        CODE_TUNNEL_NTASKS="$2";     shift 2 ;;
        --session)       CODE_TUNNEL_SESSION="$2";    shift 2 ;;
        --extra)         CODE_TUNNEL_EXTRA_ARGS="$2"; shift 2 ;;
        -h|--help)       usage ;;
        -*)              die "Unknown option: $1" ;;
        *)
            if [[ -z "$MINUTES" ]]; then
                MINUTES="$1"; shift
            else
                die "Unexpected argument: $1"
            fi
            ;;
    esac
done

###############################################################################
# Interactive prompt for minutes if not provided
###############################################################################
if [[ -z "$MINUTES" ]]; then
    read -rp "Enter number of minutes for the job: " MINUTES
fi

# Validate minutes is a positive integer
if ! [[ "$MINUTES" =~ ^[0-9]+$ ]] || [[ "$MINUTES" -le 0 ]]; then
    die "Minutes must be a positive integer, got: $MINUTES"
fi

###############################################################################
# Validate required settings
###############################################################################
[[ -n "$CODE_TUNNEL_ACCOUNT" ]]   || die "SLURM account is required. Set CODE_TUNNEL_ACCOUNT or use -a/--account."
[[ -n "$CODE_TUNNEL_PARTITION" ]] || die "SLURM partition is required. Set CODE_TUNNEL_PARTITION or use -p/--partition."

###############################################################################
# Locate the VS Code CLI binary
###############################################################################
CODE_BIN=""
# 1) Check the code-tunnel install directory (peer bin/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "$SCRIPT_DIR/bin/code" ]]; then
    CODE_BIN="$SCRIPT_DIR/bin/code"
elif [[ -x "$SCRIPT_DIR/../bin/code" ]]; then
    CODE_BIN="$(cd "$SCRIPT_DIR/../bin" && pwd)/code"
fi
# 2) Common install location
if [[ -z "$CODE_BIN" ]] && [[ -x "$HOME/.vscode-tunnel/bin/code" ]]; then
    CODE_BIN="$HOME/.vscode-tunnel/bin/code"
fi
# 3) Fall back to 'code' on PATH
if [[ -z "$CODE_BIN" ]] && command -v code >/dev/null 2>&1; then
    CODE_BIN="$(command -v code)"
fi

[[ -n "$CODE_BIN" ]] || die "Could not find the VS Code CLI ('code' binary). Is it installed?"

###############################################################################
# Verify that required tools are available
###############################################################################
command -v srun   >/dev/null 2>&1 || die "'srun' not found. Are you on a SLURM cluster?"
command -v screen >/dev/null 2>&1 || die "'screen' not found. Please install GNU Screen (or ask your sysadmin)."

###############################################################################
# Compute time formatting and session info
###############################################################################
HOURS=$((MINUTES / 60))
MINS=$((MINUTES % 60))
TIME=$(printf "%02d:%02d:00" "$HOURS" "$MINS")

START=$(date +"%Y-%m-%d %H:%M:%S")

# Portable end-time calculation (GNU date, with BSD fallback)
END_EPOCH=$(( $(date +%s) + MINUTES * 60 ))
if END=$(date -d "@$END_EPOCH" +"%Y-%m-%d %H:%M:%S" 2>/dev/null); then
    : # GNU date succeeded
elif END=$(date -r "$END_EPOCH" +"%Y-%m-%d %H:%M:%S" 2>/dev/null); then
    : # BSD date fallback
else
    END="(could not compute)"
fi

TUNNEL_INFO="=====================================
Start:          $START
Session length: $MINUTES minutes ($TIME)
End:            $END
=====================================
"
export TUNNEL_INFO
export CODE_BIN

###############################################################################
# Build srun command
###############################################################################
SRUN_ARGS=(
    srun
    -A "$CODE_TUNNEL_ACCOUNT"
    -p "$CODE_TUNNEL_PARTITION"
    --nodes "$CODE_TUNNEL_NODES"
    --ntasks "$CODE_TUNNEL_NTASKS"
    --cpus-per-task "$CODE_TUNNEL_CPUS"
    --gres="$CODE_TUNNEL_GPUS"
    -t "$TIME"
)
[[ -n "$CODE_TUNNEL_MEM" ]] && SRUN_ARGS+=(--mem="$CODE_TUNNEL_MEM")
[[ -n "$CODE_TUNNEL_QOS" ]] && SRUN_ARGS+=(--qos="$CODE_TUNNEL_QOS")

# Append any extra user-specified args (word-split intentionally)
if [[ -n "$CODE_TUNNEL_EXTRA_ARGS" ]]; then
    # shellcheck disable=SC2206
    SRUN_ARGS+=($CODE_TUNNEL_EXTRA_ARGS)
fi

SRUN_ARGS+=(
    --pty
    screen -mS "$CODE_TUNNEL_SESSION"
    bash -c 'echo "$TUNNEL_INFO"; "$CODE_BIN" tunnel; exec bash'
)

###############################################################################
# Launch
###############################################################################
echo "Requesting SLURM job: account=$CODE_TUNNEL_ACCOUNT partition=$CODE_TUNNEL_PARTITION time=$TIME"
echo "GPU=$CODE_TUNNEL_GPUS CPUs=$CODE_TUNNEL_CPUS"
echo ""
exec "${SRUN_ARGS[@]}"