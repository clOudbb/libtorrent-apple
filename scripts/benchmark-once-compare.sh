#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

MODE="local-binary"
REFERENCE_PROFILE="animeko-parity-v2"
CANDIDATE_PROFILE="qbittorrent-parity-v1"
DURATION_SECONDS="120"
INTERVAL_SECONDS="1"
OUTPUT_ROOT=""

usage() {
    cat <<'EOF'
Usage:
  scripts/benchmark-once-compare.sh [options] -- <benchmark-source-and-tracker-args>

Options:
  --mode <source|local-binary|remote-binary>   Package mode (default: local-binary)
  --reference-profile <name>                    Reference profile (default: animeko-parity-v2)
  --candidate-profile <name>                    Candidate profile (default: qbittorrent-parity-v1)
  --duration <seconds>                          Sampling window (default: 120)
  --interval <seconds>                          Sampling interval (default: 1)
  --output-root <path>                          Output root directory
  -h, --help                                    Show help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode) MODE="${2:-}"; shift 2 ;;
        --reference-profile) REFERENCE_PROFILE="${2:-}"; shift 2 ;;
        --candidate-profile) CANDIDATE_PROFILE="${2:-}"; shift 2 ;;
        --duration) DURATION_SECONDS="${2:-}"; shift 2 ;;
        --interval) INTERVAL_SECONDS="${2:-}"; shift 2 ;;
        --output-root) OUTPUT_ROOT="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

EXTRA_ARGS=("$@")
if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
    echo "Missing benchmark source/tracker args after '--'." >&2
    usage >&2
    exit 2
fi

case "${MODE}" in
    source|local-binary|remote-binary) ;;
    *) echo "Unsupported mode: ${MODE}" >&2; exit 2 ;;
esac

if [[ -z "${OUTPUT_ROOT}" ]]; then
    ts="$(date +%s)"
    OUTPUT_ROOT="${ROOT_DIR}/Build/benchmark/once-compare-${ts}"
fi

REFERENCE_DIR="${OUTPUT_ROOT}/reference-${REFERENCE_PROFILE}"
CANDIDATE_DIR="${OUTPUT_ROOT}/candidate-${CANDIDATE_PROFILE}"
COMPARE_PATH="${OUTPUT_ROOT}/compare.json"
mkdir -p "${REFERENCE_DIR}" "${CANDIDATE_DIR}"

COMMON_ARGS=(
    --duration "${DURATION_SECONDS}"
    --interval "${INTERVAL_SECONDS}"
    --disable-profile-trackers
    "${EXTRA_ARGS[@]}"
)

echo "[compare] running reference profile: ${REFERENCE_PROFILE}"
"${SCRIPT_DIR}/run-benchmark-demo.sh" "${MODE}" \
    --profile "${REFERENCE_PROFILE}" \
    --output-dir "${REFERENCE_DIR}" \
    "${COMMON_ARGS[@]}"

echo "[compare] running candidate profile: ${CANDIDATE_PROFILE}"
"${SCRIPT_DIR}/run-benchmark-demo.sh" "${MODE}" \
    --profile "${CANDIDATE_PROFILE}" \
    --output-dir "${CANDIDATE_DIR}" \
    "${COMMON_ARGS[@]}"

python3 - <<'PY' "${REFERENCE_DIR}/summary.json" "${CANDIDATE_DIR}/summary.json" "${COMPARE_PATH}"
import json
import sys
from pathlib import Path

ref_path = Path(sys.argv[1])
cand_path = Path(sys.argv[2])
out_path = Path(sys.argv[3])

ref = json.loads(ref_path.read_text())
cand = json.loads(cand_path.read_text())

ref_dl = float(ref.get("averageDownloadRateBytesPerSecond", 0) or 0)
cand_dl = float(cand.get("averageDownloadRateBytesPerSecond", 0) or 0)
ref_ul = float(ref.get("averageUploadRateBytesPerSecond", 0) or 0)
cand_ul = float(cand.get("averageUploadRateBytesPerSecond", 0) or 0)

report = {
    "referenceSummary": str(ref_path),
    "candidateSummary": str(cand_path),
    "referenceProfile": ref.get("profile"),
    "candidateProfile": cand.get("profile"),
    "referenceAverageDownloadRateBytesPerSecond": ref_dl,
    "candidateAverageDownloadRateBytesPerSecond": cand_dl,
    "downloadDeltaPercentVsReference": ((cand_dl - ref_dl) / ref_dl * 100.0) if ref_dl > 0 else None,
    "referenceAverageUploadRateBytesPerSecond": ref_ul,
    "candidateAverageUploadRateBytesPerSecond": cand_ul,
    "uploadDeltaPercentVsReference": ((cand_ul - ref_ul) / ref_ul * 100.0) if ref_ul > 0 else None,
    "referenceAveragePeers": ref.get("averagePeers"),
    "candidateAveragePeers": cand.get("averagePeers"),
    "referenceAverageSeeds": ref.get("averageSeeds"),
    "candidateAverageSeeds": cand.get("averageSeeds"),
    "referenceP95DownloadRateBytesPerSecond": ref.get("p95DownloadRateBytesPerSecond"),
    "candidateP95DownloadRateBytesPerSecond": cand.get("p95DownloadRateBytesPerSecond"),
}

out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
print(f"[compare] report: {out_path}")
PY

