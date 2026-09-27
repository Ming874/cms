#!/bin/sh
# 以 root 執行（cmsuser 透過 sudo 呼叫，只允許這一支腳本）。
#
# isolate 2.0 需要一個「已啟用 memory/cpu/pids controller」的 cgroup v2 子樹。
# 容器使用私有 cgroup namespace（compose: cgroup: private），這裡把容器內的
# cgroup 整理成：
#
#   /sys/fs/cgroup            （容器的 cgroup 根，只放子群組）
#   ├── init/                 容器內所有一般行程
#   └── isolate/              交給 isolate 建立 box-N 子群組 (cg_root)
#
# cgroup v2 規定「有啟用 controller 的非根群組不能直接放行程」，所以要先把
# 行程移到 init/，才能在根群組開啟 subtree_control。
# 這個做法不會碰到主機的 cgroup 樹，多個 CMS 容器也不會互相干擾。
set -eu

CG=/sys/fs/cgroup

die() {
    echo "[cms-cgroup-setup] 錯誤：$*" >&2
    exit 1
}

[ -f "$CG/cgroup.controllers" ] \
    || die "需要 cgroup v2（Docker Desktop / Ubuntu 22.04+ / Debian 11+ 預設即是）。"

if ! mkdir -p "$CG/init" 2>/dev/null; then
    die "無法寫入 $CG。容器必須以 privileged: true 啟動。"
fi

# 私有 cgroup namespace 下 /proc/self/cgroup 會是 "0::/..."（相對路徑很短）。
# 若使用 cgroup: host，這裡會看到主機的完整路徑，拒絕執行以免動到主機。
case "$(cat /proc/self/cgroup)" in
    0::/|0::/init) ;;
    *) die "偵測到主機 cgroup namespace（$(cat /proc/self/cgroup)），請在 compose 設定 cgroup: private。" ;;
esac

# 把根群組的行程全部移到 init/（行程可能在移動期間結束，忽略錯誤）
for _ in 1 2 3; do
    for pid in $(cat "$CG/cgroup.procs"); do
        echo "$pid" > "$CG/init/cgroup.procs" 2>/dev/null || true
    done
    [ -z "$(cat "$CG/cgroup.procs")" ] && break
done
[ -z "$(cat "$CG/cgroup.procs")" ] || die "無法清空容器根 cgroup 的行程。"

available="$(cat "$CG/cgroup.controllers")"
enable_controllers() {
    target="$1"
    for c in cpu memory pids; do
        case " $available " in
            *" $c "*) echo "+$c" > "$target/cgroup.subtree_control" ;;
        esac
    done
}

case " $available " in
    *" memory "*) ;;
    *) die "cgroup 沒有 memory controller，isolate 無法限制記憶體。" ;;
esac

enable_controllers "$CG"
mkdir -p "$CG/isolate"
enable_controllers "$CG/isolate"

echo "[cms-cgroup-setup] isolate cgroup 已就緒：$CG/isolate（controllers: $(cat "$CG/isolate/cgroup.subtree_control")）"
