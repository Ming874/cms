#!/bin/bash
# isolate 沙箱自我檢查：確認「正常執行 / 超時 / 超記憶體」三種情況都被正確判定。
# 服務啟動前會自動執行一次；失敗代表評測結果不可信，容器會拒絕啟動。
set -uo pipefail

BOX=999            # CMS 的 Worker 使用 box 10~179，這裡用不會衝突的編號
META=$(mktemp)
fail() {
    echo "[cms-sandbox-check] 失敗：$*" >&2
    isolate --cg --box-id=$BOX --cleanup >/dev/null 2>&1 || true
    rm -f "$META"
    exit 1
}

isolate --cg --box-id=$BOX --cleanup >/dev/null 2>&1 || true
BOXDIR=$(isolate --cg --box-id=$BOX --init 2>&1) || fail "isolate --init 失敗：$BOXDIR"

run() {
    isolate --cg --box-id=$BOX --meta="$META" --processes=4 --silent "$@" 2>/dev/null
}

# 1) 正常執行：C++ 編譯後在沙箱中執行
cat > "$BOXDIR/box/ok.cpp" <<'EOF'
#include <cstdio>
int main() { std::puts("sandbox-ok"); return 0; }
EOF
g++ -O2 -o "$BOXDIR/box/ok" "$BOXDIR/box/ok.cpp" || fail "g++ 編譯失敗"
out=$(run --time=2 --wall-time=5 --cg-mem=262144 --run -- ./ok) || fail "正常程式執行失敗：$(cat "$META")"
[ "$out" = "sandbox-ok" ] || fail "輸出不符：$out"

# 2) CPU 時間限制
run --time=0.5 --wall-time=5 --cg-mem=262144 --run -- /bin/sh -c 'while :; do :; done'
grep -q '^status:TO' "$META" || fail "無窮迴圈沒有被判定為超時：$(tr '\n' ' ' < "$META")"

# 3) 記憶體限制（限制 64 MiB，嘗試配置 256 MiB）
cat > "$BOXDIR/box/mle.cpp" <<'EOF'
#include <cstdlib>
#include <cstring>
int main() { char *p = (char*)std::malloc(256u << 20); std::memset(p, 1, 256u << 20); return p[12345]; }
EOF
g++ -O0 -o "$BOXDIR/box/mle" "$BOXDIR/box/mle.cpp" || fail "g++ 編譯失敗"
run --time=5 --wall-time=10 --cg-mem=65536 --run -- ./mle
grep -q '^cg-oom-killed:1' "$META" || fail "超過記憶體沒有被 cgroup 終止：$(tr '\n' ' ' < "$META")"

isolate --cg --box-id=$BOX --cleanup >/dev/null 2>&1 || true
rm -f "$META"
echo "[cms-sandbox-check] isolate 沙箱正常（執行 / 超時 / 超記憶體 皆判定正確）"
