# syntax=docker/dockerfile:1.6
# ============================================================
#  OpenHarmony / HarmonyOS Flutter 开发环境 Docker 镜像
#  适用于蜜蜂记账 (beecount-openharmony) CI/CD 构建
# ============================================================

# ---------- 可配置的构建参数 (docker build --build-arg KEY=VALUE) ----------
ARG BASE_IMAGE=ubuntu:22.04

# Flutter-OH (鸿蒙版 Flutter SDK)
ARG FLUTTER_OH_REPO=https://gitcode.com/openharmony-tpc/flutter_flutter.git
ARG FLUTTER_OH_REF=3.27.5-ohos-1.0.0

# OpenJDK 版本 (OpenHarmony SDK 要求 JDK 17)
ARG JDK_VERSION=17

# Node.js 版本 (与 DevEco Studio 捆绑版本保持一致)
ARG NODE_VERSION=18.x

# ===== DevEco Studio / Command-line Tools 下载地址 =====
# 说明：以下 URL 可能会随版本更新而变化。
# 如果默认下载失败，请从以下官方页面获取最新 Linux 版 URL：
#   https://developer.huawei.com/consumer/cn/deveco-studio/
#   https://developer.huawei.com/consumer/cn/download/
# 然后通过 --build-arg DEVECO_STUDIO_URL=... 传入。
ARG DEVECO_STUDIO_URL=https://content.deveco.cloud/developer.huawei.com/devecostudio/linux/deveco-studio-5.0.3.100-linux.tar.gz

# ===== OpenHarmony SDK 下载地址 =====
# 说明：官方 SDK 可从 OpenHarmony CI 每日构建下载：
#   https://dcp.openharmony.cn/workbench/cicd/dailybuild/dailylist
# 项目 compatibleSdkVersion = 5.0.0(12)，需要 API 12 对应的 SDK。
# 如果默认下载失败，请重新获取 ohos-sdk-public-Linux-x64-*.zip 的最新直链。
ARG OHOS_SDK_URL=https://download.ci.openharmony.cn/version/Master_Version/OpenHarmony_5.0.3.3/20250630_202440/ohos-sdk-public/linux-x64/ohos-sdk-public-Linux-x64-5.0.3.3-Release.zip

# 安装路径
ARG INSTALL_ROOT=/opt
ARG USERNAME=build
ARG USER_UID=1000
ARG USER_GID=1000

# ============================================================
#  Stage 1: 基础层 —— 系统依赖、JDK、Node、Git
# ============================================================
FROM ${BASE_IMAGE} AS base

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Asia/Shanghai

RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        git \
        unzip \
        zip \
        xz-utils \
        file \
        gnupg \
        lsb-release \
        software-properties-common \
        build-essential \
        pkg-config \
        libgl1-mesa-glx \
        libegl1-mesa \
        libxkbcommon-x11-0 \
        libstdc++-12-dev \
        libssl-dev \
        python3 \
        python3-pip \
        python3-venv \
        ssh-client \
        rsync \
    && rm -rf /var/lib/apt/lists/*

ARG JDK_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends \
        openjdk-${JDK_VERSION}-jdk \
        openjdk-${JDK_VERSION}-jre-headless \
    && rm -rf /var/lib/apt/lists/* \
    && java -version

ENV JAVA_HOME=/usr/lib/jvm/java-${JDK_VERSION}-openjdk-amd64 \
    PATH=/usr/lib/jvm/java-${JDK_VERSION}-openjdk-amd64/bin:${PATH}

ARG NODE_VERSION
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_VERSION} nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && node --version && npm --version \
    && npm config set registry https://registry.npmmirror.com

# ============================================================
#  Stage 2: 工具层 —— 下载 DevEco Studio 工具 + OpenHarmony SDK
# ============================================================
FROM base AS tools

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

ARG INSTALL_ROOT
ARG DEVECO_STUDIO_URL
ARG OHOS_SDK_URL

WORKDIR /tmp/build

ENV TOOL_HOME=${INSTALL_ROOT}/devecostudio

RUN set -eux; \
    if wget --tries=3 --timeout=60 -O deveco.tar.gz "${DEVECO_STUDIO_URL}"; then \
      echo "[INFO] DevEco Studio 下载成功，正在提取 CLI 工具..."; \
      mkdir -p "${TOOL_HOME}"; \
      tar -xzf deveco.tar.gz -C "${TOOL_HOME}" --strip-components=1 || \
        (tar -xzf deveco.tar.gz -C /tmp/build && mv /tmp/build/Deveco*/* "${TOOL_HOME}/" 2>/dev/null) || true; \
      ls -la "${TOOL_HOME}" || true; \
    else \
      echo "[WARN] DevEco Studio 下载失败，将使用备用方案 (仅安装 ohpm/hvigor CLI)"; \
      mkdir -p "${TOOL_HOME}/tools/ohpm/bin" "${TOOL_HOME}/tools/hvigor/bin" "${TOOL_HOME}/sdk"; \
    fi; \
    rm -f deveco.tar.gz

RUN set -eux; \
    if [ ! -f "${TOOL_HOME}/tools/ohpm/bin/ohpm" ]; then \
      echo "[INFO] 正在通过 npm 全局安装 ohpm-cli ..."; \
      npm install -g @ohos/hpm-cli || true; \
      if command -v hpm >/dev/null 2>&1; then \
        mkdir -p "${TOOL_HOME}/tools/ohpm/bin"; \
        ln -sf "$(command -v hpm)" "${TOOL_HOME}/tools/ohpm/bin/ohpm" || true; \
      fi; \
    fi; \
    (ls "${TOOL_HOME}/tools/ohpm/bin/" && echo "[OK] ohpm 目录") || echo "[WARN] ohpm 仍不可用"; \
    true

RUN set -eux; \
    if [ ! -f "${TOOL_HOME}/tools/hvigor/bin/hvigorw" ]; then \
      echo "[INFO] 通过 npm 安装 @ohos/hvigor-wrapper ..."; \
      npm install -g @ohos/hvigor @ohos/hvigor-wrapper || true; \
      if command -v hvigor >/dev/null 2>&1; then \
        mkdir -p "${TOOL_HOME}/tools/hvigor/bin"; \
        ln -sf "$(command -v hvigor)" "${TOOL_HOME}/tools/hvigor/bin/hvigorw" || true; \
      fi; \
    fi; \
    true

ENV DEVECO_SDK_HOME=${TOOL_HOME}/sdk \
    HOS_SDK_HOME=${TOOL_HOME}/sdk

RUN set -eux; \
    mkdir -p "${DEVECO_SDK_HOME}/default/openharmony"; \
    if wget --tries=3 --timeout=120 -O ohos-sdk.zip "${OHOS_SDK_URL}"; then \
      echo "[INFO] OpenHarmony SDK 下载成功，正在解压..."; \
      unzip -q ohos-sdk.zip -d /tmp/ohos-sdk || unzip -q ohos-sdk.zip -d /tmp/ohos-sdk -x "*/.*" || true; \
      ls -la /tmp/ohos-sdk || true; \
      if [ -d /tmp/ohos-sdk/sdk ]; then \
        cp -r /tmp/ohos-sdk/sdk/* "${DEVECO_SDK_HOME}/" 2>/dev/null || true; \
      fi; \
      if [ -d /tmp/ohos-sdk/ohos-sdk ]; then \
        cp -r /tmp/ohos-sdk/ohos-sdk/* "${DEVECO_SDK_HOME}/" 2>/dev/null || true; \
      fi; \
      mkdir -p "${DEVECO_SDK_HOME}/default/openharmony/12/ets" \
               "${DEVECO_SDK_HOME}/default/openharmony/12/js" \
               "${DEVECO_SDK_HOME}/default/openharmony/12/native" \
               "${DEVECO_SDK_HOME}/default/openharmony/12/toolchains" \
               "${DEVECO_SDK_HOME}/default/openharmony/toolchains"; \
      find /tmp/ohos-sdk -type d -name "toolchains" -not -path "*/.*" | head -n 5 | while read -r d; do \
        cp -r "$d"/* "${DEVECO_SDK_HOME}/default/openharmony/12/toolchains/" 2>/dev/null || \
        cp -r "$d"/* "${DEVECO_SDK_HOME}/default/openharmony/toolchains/" 2>/dev/null || true; \
      done; \
      find /tmp/ohos-sdk -type d -name "ets" -not -path "*/.*" | head -n 5 | while read -r d; do \
        cp -r "$d"/* "${DEVECO_SDK_HOME}/default/openharmony/12/ets/" 2>/dev/null || true; \
      done; \
      find /tmp/ohos-sdk -type d -name "js" -not -path "*/.*" | head -n 5 | while read -r d; do \
        cp -r "$d"/* "${DEVECO_SDK_HOME}/default/openharmony/12/js/" 2>/dev/null || true; \
      done; \
      find /tmp/ohos-sdk -type d \( -name "native" -o -name "nativellvm" \) -not -path "*/.*" | head -n 5 | while read -r d; do \
        cp -r "$d"/* "${DEVECO_SDK_HOME}/default/openharmony/12/native/" 2>/dev/null || true; \
      done; \
      find "${DEVECO_SDK_HOME}" -name "hdc" -type f 2>/dev/null | xargs -r chmod +x || true; \
      ls -la "${DEVECO_SDK_HOME}/default/openharmony/" || true; \
      ls -la "${DEVECO_SDK_HOME}/default/openharmony/12/" || true; \
    else \
      echo "[WARN] OpenHarmony SDK 下载失败，请稍后通过 docker run 挂载 SDK 或手动下载"; \
    fi; \
    rm -rf /tmp/ohos-sdk /tmp/build/ohos-sdk.zip; \
    true

# ============================================================
#  Stage 3: Flutter 层 —— 克隆并初始化 Flutter-OH SDK
# ============================================================
FROM tools AS flutter

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

ARG INSTALL_ROOT
ARG FLUTTER_OH_REPO
ARG FLUTTER_OH_REF

ENV FLUTTER_ROOT=${INSTALL_ROOT}/flutter \
    PUB_CACHE=${INSTALL_ROOT}/.pub-cache \
    PUB_HOSTED_URL=https://pub.flutter-io.cn \
    FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn \
    PATH=${INSTALL_ROOT}/flutter/bin:${INSTALL_ROOT}/flutter/bin/cache/dart-sdk/bin:${INSTALL_ROOT}/.pub-cache/bin:${PATH}

RUN set -eux; \
    git clone --depth 1 --branch "${FLUTTER_OH_REF}" "${FLUTTER_OH_REPO}" "${FLUTTER_ROOT}" 2>/dev/null || \
    ( \
      echo "[INFO] 指定分支/Tag不存在，尝试用 commit 或 dev 分支..."; \
      git clone "${FLUTTER_OH_REPO}" "${FLUTTER_ROOT}"; \
      cd "${FLUTTER_ROOT}"; \
      git checkout "${FLUTTER_OH_REF}" 2>/dev/null || \
        git checkout -b dev origin/dev 2>/dev/null || \
        (git tag && git checkout "$(git tag | grep -i 'ohos' | tail -n 1)") || true; \
    ); \
    cd "${FLUTTER_ROOT}"; \
    git log --oneline -n 5 || true; \
    git describe --tags --always 2>/dev/null || true; \
    ls -la bin/

RUN set -eux; \
    flutter config --no-analytics; \
    if [ -d "${HOS_SDK_HOME}/default/openharmony/12" ] || [ -d "${HOS_SDK_HOME}/default/openharmony" ]; then \
      flutter config --ohos-sdk "${HOS_SDK_HOME}" || true; \
    fi; \
    flutter --version; \
    dart --version || true; \
    flutter doctor -v || true; \
    flutter precache --platforms=ohos,web,linux || true; \
    chmod -R a+rwx "${FLUTTER_ROOT}" "${PUB_CACHE}" 2>/dev/null || true

# ============================================================
#  Stage 4: 最终镜像 —— 创建普通用户 + 入口脚本
# ============================================================
FROM flutter AS runtime

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

ARG INSTALL_ROOT
ARG USERNAME
ARG USER_UID
ARG USER_GID

RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME} \
    && chown -R ${USER_UID}:${USER_GID} ${INSTALL_ROOT} ${PUB_CACHE} 2>/dev/null || true

ENV TOOL_HOME=${INSTALL_ROOT}/devecostudio \
    DEVECO_SDK_HOME=${INSTALL_ROOT}/devecostudio/sdk \
    HOS_SDK_HOME=${INSTALL_ROOT}/devecostudio/sdk \
    FLUTTER_ROOT=${INSTALL_ROOT}/flutter \
    PUB_CACHE=${INSTALL_ROOT}/.pub-cache \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    \
    PUB_HOSTED_URL=https://pub.flutter-io.cn \
    FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn \
    \
    PATH=${INSTALL_ROOT}/flutter/bin:${INSTALL_ROOT}/flutter/bin/cache/dart-sdk/bin:${INSTALL_ROOT}/.pub-cache/bin:${INSTALL_ROOT}/devecostudio/tools/ohpm/bin:${INSTALL_ROOT}/devecostudio/tools/hvigor/bin:${INSTALL_ROOT}/devecostudio/tools/node/bin:${INSTALL_ROOT}/devecostudio/sdk/default/openharmony/12/toolchains:${INSTALL_ROOT}/devecostudio/sdk/default/openharmony/toolchains:/usr/lib/jvm/java-17-openjdk-amd64/bin:${PATH}

WORKDIR /workspace
RUN chown -R ${USER_UID}:${USER_GID} /workspace

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

USER ${USERNAME}
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/bin/bash"]
