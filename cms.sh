#!/usr/bin/env bash
# CMS Docker 管理工具（Linux / macOS / WSL / Git Bash）
#   ./cms.sh init    第一次使用：產生 .env（含隨機密碼）
#   ./cms.sh up      建置並啟動
#   ./cms.sh help    所有指令
set -euo pipefail
cd "$(dirname "$0")"
# Git Bash 會把 /backups 之類的參數轉成 Windows 路徑，關掉它
export MSYS_NO_PATHCONV=1

fail() { echo "錯誤：$*" >&2; exit 1; }
env_value() { [ -f .env ] && sed -n "s/^$1=//p" .env | tail -n1 | tr -d '\r' || true; }
need_env() { [ -f .env ] || fail "找不到 .env，請先執行 ./cms.sh init"; }
rand() { LC_ALL=C tr -dc 'A-HJ-NP-Za-km-z2-9' < /dev/urandom | head -c "$1"; }

wait_healthy() {
    local id state deadline=$((SECONDS + ${1:-300}))
    id=$(docker compose ps -q cms)
    [ -n "$id" ] || fail "cms 容器沒有在執行"
    printf '等待 CMS 啟動完成'
    while (( SECONDS < deadline )); do
        state=$(docker inspect --format '{{.State.Health.Status}}' "$id" 2>/dev/null || echo gone)
        case "$state" in
            healthy) echo " 完成"; return 0 ;;
            unhealthy|gone) break ;;
        esac
        [ "$(docker inspect --format '{{.State.Running}}' "$id" 2>/dev/null)" = "true" ] || break
        printf '.'; sleep 3
    done
    echo
    docker compose logs --tail 60 cms
    fail "CMS 沒有在時限內啟動，請看上方日誌（或 ./cms.sh logs）"
}

show_urls() {
    echo
    echo "  考生介面  ContestWebServer : http://localhost:$(env_value CWS_PORT)/"
    echo "  管理介面  AdminWebServer   : http://localhost:$(env_value AWS_PORT)/   帳號 $(env_value CMS_ADMIN_USERNAME) / 密碼見 .env 的 CMS_ADMIN_PASSWORD"
    [ "$(env_value CMS_RANKING)" = "true" ] && echo "  排名介面  RankingWebServer : http://localhost:$(env_value RWS_PORT)/"
    echo
}

db_name() { local v; v=$(env_value CMS_DB_NAME); echo "${v:-cmsdb}"; }
db_user() { local v; v=$(env_value CMS_DB_USER); echo "${v:-cmsuser}"; }

cmd="${1:-help}"; shift || true
case "$cmd" in
    init)
        [ ! -f .env ] || fail ".env 已存在；若要重新產生請先自行備份並刪除它"
        sed -e "s/^CMS_DB_PASSWORD=.*/CMS_DB_PASSWORD=$(rand 32)/" \
            -e "s/^CMS_ADMIN_PASSWORD=.*/CMS_ADMIN_PASSWORD=$(rand 16)/" \
            -e "s/^CMS_RANKING_PASSWORD=.*/CMS_RANKING_PASSWORD=$(rand 24)/" \
            .env.example | tr -d '\r' > .env
        chmod 600 .env
        mkdir -p backups config
        echo "已產生 .env（含隨機密碼）。管理員密碼：$(env_value CMS_ADMIN_PASSWORD)"
        echo "下一步：./cms.sh up"
        ;;
    up)
        need_env; mkdir -p backups config
        # 映像不存在才會建置；離線電腦先 load-image 即可直接啟動
        docker compose up -d
        wait_healthy; show_urls
        ;;
    build)    need_env; docker compose build cms ;;
    down)     docker compose down ;;
    restart)  need_env; docker compose restart cms; wait_healthy; show_urls ;;
    logs)     docker compose logs -f --tail 200 "$@" cms ;;
    status)
        docker compose ps
        docker compose exec cms supervisorctl status || true
        docker compose exec cms ps -eo pid,etime,args --forest
        ;;
    shell)    docker compose exec cms bash ;;
    exec)
        [ $# -gt 0 ] || fail "用法：./cms.sh exec <指令> [參數...]"
        docker compose exec cms "$@"
        ;;
    selftest) docker compose exec cms cms-sandbox-check ;;
    fulltest)
        # 官方功能測試：一次性容器 + 獨立的測試資料庫，不影響正式資料
        need_env
        testdb=cmsdb_fulltest
        docker compose exec -T db dropdb -U "$(db_user)" --if-exists "$testdb"
        docker compose exec -T db createdb -U "$(db_user)" -O "$(db_user)" "$testdb"
        rc=0
        # fulltest 服務不掛載正式資料的 volume（見 compose.yaml）
        docker compose run --rm -T fulltest cms-fulltest ${1:+"$*"} || rc=$?
        docker compose exec -T db dropdb -U "$(db_user)" --if-exists "$testdb"
        exit $rc
        ;;
    backup)
        need_env; mkdir -p backups
        name="$(db_name)-$(date +%Y%m%d-%H%M%S).dump"
        docker compose exec -T db pg_dump -U "$(db_user)" -d "$(db_name)" -Fc -f "/backups/$name"
        echo "已備份到 backups/$name"
        ;;
    restore)
        need_env
        [ $# -gt 0 ] || fail "用法：./cms.sh restore <backups 資料夾內的檔名>"
        file=$(basename "$1")
        [ -f "backups/$file" ] || fail "找不到 backups/$file"
        read -r -p "將以 $file 覆蓋目前資料庫 $(db_name)（目前資料會消失）。輸入 yes 繼續：" ans
        [ "$ans" = "yes" ] || fail "已取消"
        docker compose stop cms
        docker compose exec -T db dropdb -U "$(db_user)" --if-exists "$(db_name)"
        docker compose exec -T db createdb -U "$(db_user)" -O "$(db_user)" "$(db_name)"
        docker compose exec -T db pg_restore -U "$(db_user)" -d "$(db_name)" --no-owner "/backups/$file"
        docker compose start cms
        wait_healthy
        echo "還原完成"
        ;;
    save-image)
        need_env
        out="cms-images-$(date +%Y%m%d).tar"
        mapfile -t images < <(docker compose config --images)
        docker save -o "$out" "${images[@]}"
        echo "已匯出 ${images[*]} 到 $out"
        echo "在其他電腦：複製整個資料夾與 $out，執行 ./cms.sh load-image $out 再 ./cms.sh init / up"
        ;;
    load-image)
        [ $# -gt 0 ] || fail "用法：./cms.sh load-image <tar 檔>"
        docker load -i "$1"
        ;;
    destroy)
        read -r -p "將刪除所有容器與資料（資料庫、提交、日誌），無法復原。輸入 DELETE 繼續：" ans
        [ "$ans" = "DELETE" ] || fail "已取消"
        docker compose down -v
        ;;
    *)
        cat <<'EOF'
CMS Docker 管理工具

  ./cms.sh init                 第一次使用：由 .env.example 產生 .env（隨機密碼）
  ./cms.sh up                   啟動（映像不存在時自動建置；已啟動則套用 .env 變更）
  ./cms.sh build                重新建置映像（修改 docker/ 內檔案或版本後）
  ./cms.sh down                 停止並移除容器（資料保留在 volume）
  ./cms.sh restart              重新啟動 CMS 容器
  ./cms.sh status               容器、服務、行程狀態
  ./cms.sh logs                 即時日誌（Ctrl+C 離開）
  ./cms.sh shell                進入容器（可直接使用 cmsAddUser 等所有 CMS 指令）
  ./cms.sh exec <指令...>       在容器內執行單一 CMS 指令
  ./cms.sh selftest             重新檢查 isolate 沙箱（數秒）
  ./cms.sh fulltest             執行 CMS 官方功能測試，驗證完整評測流程（數分鐘）
  ./cms.sh backup               備份資料庫到 backups/
  ./cms.sh restore <檔名>       從 backups/ 還原資料庫
  ./cms.sh save-image           匯出映像檔（離線 / 其他電腦部署）
  ./cms.sh load-image <tar>     匯入映像檔
  ./cms.sh destroy              刪除所有容器與資料
EOF
        ;;
esac
