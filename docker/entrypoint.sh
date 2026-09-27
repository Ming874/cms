#!/bin/bash
# CMS 容器進入點（以 cmsuser 執行，PID 1 是 tini）
#
#   serve（預設） 完整啟動：cgroup → 設定檔 → 等資料庫 → 初始化 → 沙箱檢查 → supervisord
#   其他指令      只產生設定檔並等資料庫，然後執行該指令（例如 bash、cmsDumpImporter ...）
set -euo pipefail

log() { echo "[cms-entrypoint] $*"; }

export CMS_CONTEST_ID="${CMS_CONTEST_ID:-ALL}"
export CMS_RANKING="${CMS_RANKING:-false}"
export PGHOST="${CMS_DB_HOST:-db}" PGPORT="${CMS_DB_PORT:-5432}"
export PGUSER="${CMS_DB_USER:-cmsuser}" PGDATABASE="${CMS_DB_NAME:-cmsdb}"
export PGPASSWORD="${CMS_DB_PASSWORD:-}"

wait_for_db() {
    local timeout="${CMS_DB_WAIT_SECONDS:-120}" waited=0
    until pg_isready -q -t 2; do
        if (( waited >= timeout )); then
            log "錯誤：${timeout} 秒內無法連上資料庫 ${PGHOST}:${PGPORT}"
            exit 1
        fi
        sleep 2; waited=$((waited + 2))
    done
    # pg_isready 只代表可連線，再確認帳密正確
    if ! psql -qtAc 'SELECT 1' >/dev/null; then
        log "錯誤：資料庫帳號或密碼不正確（CMS_DB_USER / CMS_DB_PASSWORD）"
        exit 1
    fi
}

init_db_if_needed() {
    if [ "$(psql -qtAc "SELECT to_regclass('public.contests') IS NOT NULL")" = "t" ]; then
        log "資料庫已初始化"
    else
        log "第一次啟動：初始化資料庫（cmsInitDB）"
        cmsInitDB
    fi
}

ensure_admin() {
    local user="${CMS_ADMIN_USERNAME:-}" pass="${CMS_ADMIN_PASSWORD:-}"
    [ -n "$user" ] && [ -n "$pass" ] || return 0
    local exists
    # CMS 會把 "Using configuration file" 日誌印到 stdout，只取最後一行的計數
    exists=$(CMS_ADMIN_USERNAME="$user" python - <<'EOF' | tail -n 1
import os
from cms.db import SessionGen, Admin
with SessionGen() as s:
    print(s.query(Admin).filter(Admin.username == os.environ["CMS_ADMIN_USERNAME"]).count())
EOF
)
    case "$exists" in
        0)
            log "建立管理員帳號：$user"
            cmsAddAdmin -p "$pass" "$user" ;;
        1) ;;
        *)
            log "錯誤：無法查詢管理員帳號（輸出：$exists）"
            exit 1 ;;
    esac
}

cleanup_old_logs() {
    local days="${CMS_LOG_RETENTION_DAYS:-30}"
    [ "$days" -gt 0 ] 2>/dev/null || return 0
    find /var/local/log/cms -type f -name '*.log' -mtime +"$days" -delete 2>/dev/null || true
}

cms-render-config

if [ "${1:-serve}" != "serve" ]; then
    wait_for_db
    exec "$@"
fi

log "CMS $(python -c 'import cms; print(cms.__version__)' 2>/dev/null | tail -n 1)，考場模式：${CMS_CONTEST_ID}"
sudo -n /usr/local/sbin/cms-cgroup-setup
wait_for_db
init_db_if_needed
ensure_admin
cleanup_old_logs
if [ "${CMS_SKIP_SANDBOX_CHECK:-false}" != "true" ]; then
    cms-sandbox-check
fi

if [ "$CMS_CONTEST_ID" = "ALL" ]; then
    log "多考場模式：考生於 http://<主機>:8888/ 選擇考場；此模式下 ProxyService 不會啟動，排名網站收不到成績"
fi
log "啟動服務"
exec supervisord -c /etc/supervisor/supervisord.conf
