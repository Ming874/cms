#!/bin/bash
# 以 CMS 官方功能測試（cmstestsuite）驗證完整評測流程：
# 提交 → 編譯 → isolate 沙箱執行 → 評分，涵蓋超時、超記憶體、禁止寫檔、互動題等情況。
# 由 cms.ps1 / cms.sh 的 fulltest 在「一次性容器 + 獨立測試資料庫」中呼叫，不影響正式資料。
set -euo pipefail

LANGS="${1:-C11 / gcc,C++11 / g++,C++17 / g++,C++20 / g++,Java / JDK,Pascal / fpc,Python 3 / CPython}"
LOG=/tmp/fulltest.log

sudo -n /usr/local/sbin/cms-cgroup-setup
cmsInitDB >/dev/null 2>&1

# 測試框架以相對路徑呼叫 cmscontrib/*.py，必須在原始碼根目錄執行
rm -rf /tmp/cms-src
cp -r /opt/cms-src /tmp/cms-src
cd /tmp/cms-src
export CMS_CONFIG=/usr/local/etc/cms.conf

echo "[cms-fulltest] 執行 CMS 官方功能測試，語言：$LANGS"
echo "[cms-fulltest] 約需 1–5 分鐘..."
set +e
cmsRunFunctionalTests -l "$LANGS" > "$LOG" 2>&1
rc=$?
set -e

if grep -q "All tests passed" "$LOG"; then
    grep -E "Executed:|Failed:|All tests passed" "$LOG" | sed 's/^.*INFO \[<unknown>\] /[cms-fulltest] /'
else
    grep -v -E "Exception ignored|after_fork_in_child|assert not|\^\^\^|AssertionError|^Traceback|^  File " "$LOG" | tail -60
    echo "[cms-fulltest] 測試未通過（exit $rc）"
fi
exit $rc
