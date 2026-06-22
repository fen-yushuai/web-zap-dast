#!/usr/bin/env bash
# Report aggregation script
# Usage: ./scripts/report.sh [REPORT_DIR]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/common.sh"

# --- Determine report directory ---
REPORT_DIR="${1:-}"
if [[ -z "$REPORT_DIR" ]]; then
  # Use latest report directory
  REPORT_DIR=$(ls -dt "${REPORTS_DIR}"/*/ 2>/dev/null | head -1 || true)
  if [[ -z "$REPORT_DIR" ]]; then
    log_error "No report directories found in ${REPORTS_DIR}"
    exit 1
  fi
fi

REPORT_DIR="${REPORT_DIR%/}"
SUMMARY="${REPORT_DIR}/summary.md"

log_info "=== Generating Combined Report ==="
log_info "Report dir: ${REPORT_DIR}"

# --- Build summary ---
{
  echo "# DAST 扫描报告"
  echo ""
  echo "- **日期**: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "- **目标**: ${TARGET_URL}"
  echo "- **目录**: ${REPORT_DIR}"
  echo ""

  # Spider section
  echo "## Spider 爬取结果"
  echo ""
  if [[ -f "${REPORT_DIR}/zap-spider-summary.txt" ]]; then
    sed -n '/^--- 结果 ---$/,/^--- 配置 ---$/p' "${REPORT_DIR}/zap-spider-summary.txt" | grep -v "^---" | grep -v "^$" || echo "无结果"
  else
    echo "_未运行 Spider 或无结果_"
  fi
  echo ""

  # ZAP section
  echo "## ZAP 扫描发现"
  echo ""
  if [[ -f "${REPORT_DIR}/zap-summary.txt" ]]; then
    sed -n '/按风险级别统计/,/^$/p' "${REPORT_DIR}/zap-summary.txt" | grep -v "按风险级别统计" | grep -v "^---" | grep -v "^$" || echo "无告警"
    echo ""
    echo "完整报告: \`zap-report.html\` / \`zap-report.json\`"
  else
    echo "_未运行扫描或无结果_"
  fi
  echo ""

  # File listing
  echo "## 报告文件"
  echo ""
  echo "| 文件 | 说明 |"
  echo "|------|------|"
  echo "| \`zap-spider-urls.txt\` | Spider 发现的 URL 列表 |"
  echo "| \`zap-sitemap.txt\` | 站点树结构 |"
  echo "| \`zap-report.html\` | ZAP 报告（HTML） |"
  echo "| \`zap-report.json\` | ZAP 发现（JSON） |"
  echo "| \`zap-report.xml\` | ZAP 发现（XML） |"
} > "${SUMMARY}"

log_success "=== Report generated ==="
log_success "Summary: ${SUMMARY}"
echo ""
cat "${SUMMARY}"
