#!/bin/bash
set -euo pipefail

# =============================================================
#  Docker 容器入口脚本
#  功能：
#   1. 启动时检测 OpenHarmony SDK 并配置 Flutter OHOS SDK 路径
#   2. 支持用户通过 VOLUME 挂载自己的 SDK 目录覆盖镜像内默认 SDK
#   3. 打印环境信息供排错
# =============================================================

log_info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
log_ok()    { echo -e "\033[1;32m[ OK ]\033[0m  $*"; }
log_error() { echo -e "\033[1;31m[ERR ]\033[0m  $*"; }

# ---------- 1. 如果用户通过环境变量指定了额外的 SDK 路径，则覆盖 ----------
if [ -n "${CUSTOM_HOS_SDK_HOME:-}" ] && [ -d "${CUSTOM_HOS_SDK_HOME}" ]; then
  log_info "使用用户自定义 HOS_SDK_HOME: ${CUSTOM_HOS_SDK_HOME}"
  export HOS_SDK_HOME="${CUSTOM_HOS_SDK_HOME}"
  export DEVECO_SDK_HOME="${CUSTOM_HOS_SDK_HOME}"
fi

# ---------- 2. 自动把 Flutter 指向 OHOS SDK ----------
if command -v flutter >/dev/null 2>&1; then
  if [ -d "${HOS_SDK_HOME}/default/openharmony" ] || [ -d "${HOS_SDK_HOME}" ]; then
    log_info "flutter config --ohos-sdk ${HOS_SDK_HOME}"
    flutter config --ohos-sdk "${HOS_SDK_HOME}" >/dev/null 2>&1 || true
  else
    log_warn "未检测到有效 OpenHarmony SDK 目录: ${HOS_SDK_HOME}"
    log_warn "  您可以："
    log_warn "   1) 挂载 SDK: docker run -v /path/to/sdk:${HOS_SDK_HOME} ..."
    log_warn "   2) 指定环境变量: -e CUSTOM_HOS_SDK_HOME=/your/sdk"
  fi
fi

# ---------- 3. 打印环境信息 ----------
echo ""
log_info "==================== 开发环境信息 ===================="
echo "  OS:             $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '\"' || uname -a)"
echo "  Java:           $(java -version 2>&1 | head -n 1 || echo N/A)"
echo "  Node:           $(node --version 2>/dev/null || echo N/A)"
echo "  npm:            $(npm --version 2>/dev/null || echo N/A)"
echo "  ohpm:           $(ohpm --version 2>/dev/null || command -v ohpm 2>/dev/null || echo N/A)"
echo "  hvigor:         $(hvigor --version 2>/dev/null || command -v hvigorw 2>/dev/null || echo N/A)"
echo "  Flutter:        $(flutter --version 2>/dev/null | head -n 1 || echo N/A)"
echo "  Dart:           $(dart --version 2>/dev/null || echo N/A)"
echo "  hdc:            $(hdc -v 2>/dev/null || find "${HOS_SDK_HOME}" -name hdc -type f 2>/dev/null | head -n 1 || echo N/A)"
echo "  FLUTTER_ROOT:   ${FLUTTER_ROOT:-N/A}"
echo "  HOS_SDK_HOME:   ${HOS_SDK_HOME:-N/A}"
echo "  PUB_CACHE:      ${PUB_CACHE:-N/A}"
echo "  JAVA_HOME:      ${JAVA_HOME:-N/A}"
log_info "======================================================="
echo ""

# ---------- 4. 执行用户命令 ----------
if [ $# -eq 0 ]; then
  exec /bin/bash
else
  log_info "执行命令: $*"
  exec "$@"
fi
