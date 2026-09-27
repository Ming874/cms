# syntax=docker/dockerfile:1
#
# CMS (IOI Contest Management System) 執行映像
#
#   - 以 Ubuntu 24.04 為基底（與實驗室安裝文件相同）
#   - CMS 安裝在 /opt/cms-venv 的 Python venv 中
#   - isolate 沙箱使用 CMS 內附的 submodule 版本（isolate 2.0，cgroup v2）
#   - 服務以非 root 的 cmsuser 執行，由 supervisord 管理
#
# 建置：docker compose build   （參數見 compose.yaml / .env）

ARG UBUNTU_IMAGE=ubuntu:24.04
FROM ${UBUNTU_IMAGE}

# CMS 版本：tag 與對應的 commit（commit 用來防止 tag 被改動，留空則不檢查）
ARG CMS_REF=v1.5.1
ARG CMS_COMMIT=7c9fec8aa1a25ec93d624aebf815804dd93df9db
# Java 版本（實驗室安裝文件使用 openjdk-11）
ARG JDK_PACKAGE=openjdk-11-jdk-headless
# 額外語言：pypy3、php、rust、haskell、C#（體積較大，預設不裝）
ARG EXTRA_LANGS=false

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Asia/Taipei \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1

# ---------------------------------------------------------------------------
# 系統套件：編譯器 / CMS 相依函式庫 / 營運工具
# ---------------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        "${JDK_PACKAGE}" \
        fp-compiler \
        python3.12 \
        python3.12-dev \
        python3.12-venv \
        cppreference-doc-en-html \
        libcap-dev \
        libcups2-dev \
        libffi-dev \
        libpq-dev \
        libyaml-dev \
        postgresql-client \
        shared-mime-info \
        zip \
        unzip \
        git \
        ca-certificates \
        curl \
        sudo \
        supervisor \
        tini \
        tzdata \
        procps \
        less \
        nano; \
    if [ "${EXTRA_LANGS}" = "true" ]; then \
        apt-get install -y --no-install-recommends pypy3 php-cli rustc ghc mono-mcs; \
    fi; \
    rm -rf /var/lib/apt/lists/*

# 固定 UID/GID（ubuntu:24.04 已內建 uid 1000 的 ubuntu 使用者，避開它）
RUN groupadd --gid 2000 cmsuser \
 && useradd --uid 2000 --gid 2000 --create-home --shell /bin/bash cmsuser

# ---------------------------------------------------------------------------
# 取得 CMS 原始碼（含 isolate submodule）並驗證 commit
# ---------------------------------------------------------------------------
WORKDIR /opt/cms-src
RUN set -eux; \
    git clone --depth 1 --branch "${CMS_REF}" --recurse-submodules \
        https://github.com/cms-dev/cms.git .; \
    if [ -n "${CMS_COMMIT}" ]; then \
        test "$(git rev-parse HEAD)" = "${CMS_COMMIT}" \
          || { echo "CMS ${CMS_REF} 的 commit 與預期不符"; exit 1; }; \
    fi

# ---------------------------------------------------------------------------
# Python venv + 相依套件（constraints.txt 鎖定所有版本以確保可重現）
# ---------------------------------------------------------------------------
ENV CMS_VENV=/opt/cms-venv
ENV PATH=${CMS_VENV}/bin:${PATH}
COPY constraints.txt /opt/cms-docker/constraints.txt
RUN set -eux; \
    python3.12 -m venv "${CMS_VENV}"; \
    # CMS 1.5 執行期仍 import pkg_resources，新版 setuptools 已移除它
    # （實驗室文件中 "No module named 'pkg_resources'" 的根因），必須維持 <70
    pip install -c /opt/cms-docker/constraints.txt "setuptools<70" wheel; \
    pip install -c /opt/cms-docker/constraints.txt -r requirements.txt; \
    pip install -c /opt/cms-docker/constraints.txt "beautifulsoup4>=4.8,<4.14"; \
    pip install --no-build-isolation --no-deps .; \
    python -c "import pkg_resources, cms; print('CMS', cms.__version__)"

# ---------------------------------------------------------------------------
# isolate + 設定檔 + 目錄（CMS 官方的 prerequisites.py）
# ---------------------------------------------------------------------------
RUN set -eux; \
    python3.12 prerequisites.py --yes --as-root --cmsuser=cmsuser install; \
    # isolate 使用容器內自己的 cgroup 子樹（由 cms-cgroup-setup 建立）
    sed -i 's|^cg_root.*|cg_root = /sys/fs/cgroup/isolate|' /usr/local/etc/isolate; \
    grep -q '^cg_root = /sys/fs/cgroup/isolate$' /usr/local/etc/isolate; \
    # 保留設定樣板，執行時由 cms-render-config 產生實際設定
    mkdir -p /opt/cms-docker; \
    cp config/cms.conf.sample config/cms.ranking.conf.sample /opt/cms-docker/; \
    # 考生介面的離線文件：CWS 連到 docs/<副檔名>/index.html，
    # 保留 cppreference 的目錄結構（en/、common/）讓頁面內的相對連結正常
    for lang in cpp c; do \
        mkdir -p "/usr/share/cms/docs/${lang}"; \
        ln -s /usr/share/cppreference/doc/html/en "/usr/share/cms/docs/${lang}/en"; \
        ln -s /usr/share/cppreference/doc/html/common "/usr/share/cms/docs/${lang}/common"; \
    done; \
    echo '<meta http-equiv="refresh" content="0; url=en/Main_Page.html">' > /usr/share/cms/docs/cpp/index.html; \
    echo '<meta http-equiv="refresh" content="0; url=en/c.html">' > /usr/share/cms/docs/c/index.html; \
    test -f /usr/share/cms/docs/cpp/en/Main_Page.html; \
    test -f /usr/share/cms/docs/c/en/c.html; \
    # 備份目錄
    install -d -o cmsuser -g cmsuser -m 0775 /backups

# ---------------------------------------------------------------------------
# 容器啟動腳本
# ---------------------------------------------------------------------------
COPY entrypoint.sh       /usr/local/bin/cms-entrypoint
COPY render-config.py    /usr/local/bin/cms-render-config
COPY sandbox-check.sh    /usr/local/bin/cms-sandbox-check
COPY fulltest.sh         /usr/local/bin/cms-fulltest
COPY cgroup-setup.sh     /usr/local/sbin/cms-cgroup-setup
# 放在預設路徑，容器內直接打 supervisorctl status 即可
COPY supervisord.conf    /etc/supervisor/supervisord.conf
RUN set -eux; \
    # 防止 Windows 換行（CRLF）混入造成 "bad interpreter"
    sed -i 's/\r$//' /usr/local/bin/cms-entrypoint /usr/local/bin/cms-render-config \
        /usr/local/bin/cms-sandbox-check /usr/local/bin/cms-fulltest \
        /usr/local/sbin/cms-cgroup-setup /etc/supervisor/supervisord.conf; \
    chmod 0755 /usr/local/bin/cms-entrypoint /usr/local/bin/cms-render-config \
        /usr/local/bin/cms-sandbox-check /usr/local/bin/cms-fulltest; \
    chown root:root /usr/local/sbin/cms-cgroup-setup; \
    chmod 0755 /usr/local/sbin/cms-cgroup-setup; \
    # cmsuser 只能以 root 執行 cgroup 設定這一支腳本
    echo 'cmsuser ALL=(root) NOPASSWD: /usr/local/sbin/cms-cgroup-setup' > /etc/sudoers.d/cms-cgroup; \
    chmod 0440 /etc/sudoers.d/cms-cgroup; \
    visudo -c

LABEL org.opencontainers.image.title="cms" \
      org.opencontainers.image.description="IOI Contest Management System ${CMS_REF}" \
      org.opencontainers.image.source="https://github.com/cms-dev/cms" \
      org.opencontainers.image.version="${CMS_REF}"

USER cmsuser
WORKDIR /home/cmsuser

# 8888 考生介面 / 8889 管理介面 / 8890 排名介面
EXPOSE 8888 8889 8890

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
    CMD curl -fsS -o /dev/null http://127.0.0.1:8889/ && curl -fsS -o /dev/null http://127.0.0.1:8888/ || exit 1

STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/cms-entrypoint"]
CMD ["serve"]
