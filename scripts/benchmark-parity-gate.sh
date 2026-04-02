#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

MODE="local-binary"
REFERENCE_PROFILE="animeko-parity-v2"
CANDIDATE_PROFILE="qbittorrent-parity-v1"
THRESHOLD_PERCENT="15"
DURATION_SECONDS="300"
INTERVAL_SECONDS="1"
OUTPUT_ROOT=""

usage() {
    cat <<'EOF'
Usage:
  scripts/benchmark-parity-gate.sh [options] -- <benchmark-source-and-tracker-args>

Options:
  --mode <source|local-binary|remote-binary>   Package mode (default: local-binary)
  --reference-profile <name>                    Reference profile (default: animeko-parity-v2)
  --candidate-profile <name>                    Candidate profile (default: qbittorrent-parity-v1)
  --threshold-percent <number>                  Max allowed absolute rate gap in % (default: 15)
  --duration <seconds>                          Sampling window (default: 300)
  --interval <seconds>                          Sampling interval (default: 1)
  --output-root <path>                          Output root directory (default: Build/benchmark/parity-gate-<ts>)
  -h, --help                                    Show this help

Notes:
  - This script enforces fair A/B by running two profiles with the same input sources, trackers, and window.
  - Pass source/tracker args after '--', for example:
      --sources-file /tmp/sources.txt --tracker-file /tmp/trackers.txt
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="${2:-}"
            shift 2
            ;;
        --reference-profile)
            REFERENCE_PROFILE="${2:-}"
            shift 2
            ;;
        --candidate-profile)
            CANDIDATE_PROFILE="${2:-}"
            shift 2
            ;;
        --threshold-percent)
            THRESHOLD_PERCENT="${2:-}"
            shift 2
            ;;
        --duration)
            DURATION_SECONDS="${2:-}"
            shift 2
            ;;
        --interval)
            INTERVAL_SECONDS="${2:-}"
            shift 2
            ;;
        --output-root)
            OUTPUT_ROOT="${2:-}"
            shift 2
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
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

EXTRA_ARGS=("$@")

case "${MODE}" in
    source|local-binary|remote-binary)
        ;;
    *)
        echo "Unsupported mode: ${MODE}" >&2
        exit 2
        ;;
esac

if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
    echo "Missing benchmark source/tracker args after '--'." >&2
    usage >&2
    exit 2
fi

has_source_arg=false
has_tracker_arg=false
for arg in "${EXTRA_ARGS[@]}"; do
    if [[ "${arg}" == "--magnet" || "${arg}" == "--torrent-file" || "${arg}" == "--sources-file" ]]; then
        has_source_arg=true
    fi
    if [[ "${arg}" == "--tracker" || "${arg}" == "--tracker-file" ]]; then
        has_tracker_arg=true
    fi
done

if [[ "${has_source_arg}" != true ]]; then
    echo "At least one source input is required (--magnet/--torrent-file/--sources-file)." >&2
    exit 2
fi

if [[ "${has_tracker_arg}" != true ]]; then
    echo "At least one explicit tracker input is required (--tracker/--tracker-file) for fair A/B." >&2
    exit 2
fi

if [[ -z "${OUTPUT_ROOT}" ]]; then
    ts="$(date +%s)"
    OUTPUT_ROOT="${ROOT_DIR}/Build/benchmark/parity-gate-${ts}"
fi

REFERENCE_DIR="${OUTPUT_ROOT}/reference-${REFERENCE_PROFILE}"
CANDIDATE_DIR="${OUTPUT_ROOT}/candidate-${CANDIDATE_PROFILE}"
REPORT_PATH="${OUTPUT_ROOT}/gate_report.json"

mkdir -p "${REFERENCE_DIR}" "${CANDIDATE_DIR}"

COMMON_ARGS=(
    --duration "${DURATION_SECONDS}"
    --interval "${INTERVAL_SECONDS}"
    --disable-profile-trackers
    "${EXTRA_ARGS[@]}"
)

echo "[gate] running reference profile: ${REFERENCE_PROFILE}"
"${SCRIPT_DIR}/run-benchmark-demo.sh" "${MODE}" \
    --profile "${REFERENCE_PROFILE}" \
    --output-dir "${REFERENCE_DIR}" \
    "${COMMON_ARGS[@]}"

echo "[gate] running candidate profile: ${CANDIDATE_PROFILE}"
"${SCRIPT_DIR}/run-benchmark-demo.sh" "${MODE}" \
    --profile "${CANDIDATE_PROFILE}" \
    --output-dir "${CANDIDATE_DIR}" \
    "${COMMON_ARGS[@]}"

python3 - <<'PY' "${REFERENCE_DIR}/summary.json" "${CANDIDATE_DIR}/summary.json" "${THRESHOLD_PERCENT}" "${REPORT_PATH}"
import json
import math
import sys
from pathlib import Path

reference_path = Path(sys.argv[1])
candidate_path = Path(sys.argv[2])
threshold = float(sys.argv[3])
report_path = Path(sys.argv[4])

reference = json.loads(reference_path.read_text())
candidate = json.loads(candidate_path.read_text())

ref_rate = float(reference.get("averageDownloadRateBytesPerSecond", 0) or 0)
cand_rate = float(candidate.get("averageDownloadRateBytesPerSecond", 0) or 0)

if ref_rate <= 0:
    abs_gap_percent = None
    gate_passed = False
else:
    abs_gap_percent = abs(cand_rate - ref_rate) / ref_rate * 100.0
    gate_passed = abs_gap_percent <= threshold

hints = []
ref_peers = float(reference.get("averagePeers", 0) or 0)
cand_peers = float(candidate.get("averagePeers", 0) or 0)
ref_seeds = float(reference.get("averageSeeds", 0) or 0)
cand_seeds = float(candidate.get("averageSeeds", 0) or 0)

if ref_peers > 0 and cand_peers < ref_peers * 0.8:
    hints.append("candidate average peers is significantly lower than reference; source/tracker quality likely dominates.")
if ref_seeds > 0 and cand_seeds < ref_seeds * 0.8:
    hints.append("candidate average seeds is significantly lower than reference; swarm availability likely dominates.")

ref_startup = reference.get("firstEffectiveDownloadSeconds")
cand_startup = candidate.get("firstEffectiveDownloadSeconds")
if isinstance(ref_startup, (int, float)) and isinstance(cand_startup, (int, float)):
    if cand_startup > ref_startup + 15:
        hints.append("candidate first effective download starts later than reference.")

ref_stability = float(reference.get("connectionStabilityStdDev", 0) or 0)
cand_stability = float(candidate.get("connectionStabilityStdDev", 0) or 0)
if cand_stability > max(ref_stability * 1.2, ref_stability + 5):
    hints.append("candidate connection stability is worse (higher std-dev of total connections).")

if not hints and ref_rate > 0 and cand_rate < ref_rate:
    hints.append("candidate is slower under similar peer/seed conditions; inspect request queue, disk queue, and apply cadence.")

report = {
    "referenceSummary": str(reference_path),
    "candidateSummary": str(candidate_path),
    "thresholdPercent": threshold,
    "referenceAverageDownloadRateBytesPerSecond": ref_rate,
    "candidateAverageDownloadRateBytesPerSecond": cand_rate,
    "absoluteRateGapPercent": abs_gap_percent,
    "passed": gate_passed,
    "hints": hints,
}

report_path.parent.mkdir(parents=True, exist_ok=True)
report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")

print(f"[gate] report: {report_path}")
print(f"[gate] reference avg download: {ref_rate:.2f} B/s")
print(f"[gate] candidate avg download: {cand_rate:.2f} B/s")
if abs_gap_percent is None:
    print("[gate] absolute gap: N/A (reference avg download <= 0)")
else:
    print(f"[gate] absolute gap: {abs_gap_percent:.2f}% (threshold {threshold:.2f}%)")
print(f"[gate] result: {'PASS' if gate_passed else 'FAIL'}")
PY

