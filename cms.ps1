<#
.SYNOPSIS
  CMS Docker 管理工具（Windows PowerShell 5.1+）
  請透過 cms.cmd 呼叫（cmd 與 PowerShell 皆可，且不受執行原則限制）。

.EXAMPLE
  .\cms.cmd init          # 第一次使用：產生 .env（含隨機密碼）
  .\cms.cmd up            # 建置並啟動
  .\cms.cmd help          # 所有指令
#>
param(
    [Parameter(Position = 0)][string]$Command = "help",
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Fail([string]$msg) { Write-Host "錯誤：$msg" -ForegroundColor Red; exit 1 }

function Invoke-Compose {
    & docker compose @args
    if ($LASTEXITCODE -ne 0) { Fail "docker compose $($args -join ' ') 失敗（exit $LASTEXITCODE）" }
}

function New-RandomString([int]$Length = 24) {
    $chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789".ToCharArray()
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] $Length
    $rng.GetBytes($bytes)
    -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

function Get-EnvValue([string]$Key) {
    if (-not (Test-Path .env)) { return $null }
    foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $PSScriptRoot ".env"))) {
        if ($line -match "^\s*$Key=(.*)$") { return $Matches[1].Trim() }
    }
    return $null
}

function Assert-Env { if (-not (Test-Path .env)) { Fail "找不到 .env，請先執行 .\cms.cmd init" } }

function Wait-Healthy([int]$TimeoutSec = 300) {
    $id = (& docker compose ps -q cms)
    if (-not $id) { Fail "cms 容器沒有在執行" }
    Write-Host "等待 CMS 啟動完成" -NoNewline
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $state = (& docker inspect --format "{{.State.Health.Status}}" $id)
        if ($state -eq "healthy") { Write-Host " 完成" -ForegroundColor Green; return }
        if ($state -eq "unhealthy") { break }
        $running = (& docker inspect --format "{{.State.Running}}" $id)
        if ($running -ne "true") { break }
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 3
    }
    Write-Host ""
    & docker compose logs --tail 60 cms
    Fail "CMS 沒有在時限內啟動，請看上方日誌（或 .\cms.cmd logs）"
}

function Show-Urls {
    $cws = Get-EnvValue "CWS_PORT"; if (-not $cws) { $cws = "8888" }
    $aws = Get-EnvValue "AWS_PORT"; if (-not $aws) { $aws = "8889" }
    $rws = Get-EnvValue "RWS_PORT"; if (-not $rws) { $rws = "8890" }
    Write-Host ""
    Write-Host "  考生介面  ContestWebServer : http://localhost:$cws/"
    Write-Host "  管理介面  AdminWebServer   : http://localhost:$aws/   帳號 $(Get-EnvValue 'CMS_ADMIN_USERNAME') / 密碼見 .env 的 CMS_ADMIN_PASSWORD"
    if ((Get-EnvValue "CMS_RANKING") -eq "true") {
        Write-Host "  排名介面  RankingWebServer : http://localhost:$rws/"
    }
    Write-Host ""
}

switch ($Command) {
    "init" {
        if (Test-Path .env) { Fail ".env 已存在；若要重新產生請先自行備份並刪除它" }
        $content = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot ".env.example"), $Utf8NoBom)
        $content = $content -replace "(?m)^CMS_DB_PASSWORD=.*$", "CMS_DB_PASSWORD=$(New-RandomString 32)"
        $content = $content -replace "(?m)^CMS_ADMIN_PASSWORD=.*$", "CMS_ADMIN_PASSWORD=$(New-RandomString 16)"
        $content = $content -replace "(?m)^CMS_RANKING_PASSWORD=.*$", "CMS_RANKING_PASSWORD=$(New-RandomString 24)"
        $content = $content -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot ".env"), $content, $Utf8NoBom)
        New-Item -ItemType Directory -Force backups, config | Out-Null
        Write-Host "已產生 .env（含隨機密碼）。管理員密碼：$(Get-EnvValue 'CMS_ADMIN_PASSWORD')" -ForegroundColor Green
        Write-Host "下一步：.\cms.cmd up"
    }
    "up" {
        Assert-Env
        New-Item -ItemType Directory -Force backups, config | Out-Null
        # 映像不存在才會建置；離線電腦先 load-image 即可直接啟動
        Invoke-Compose up -d
        Wait-Healthy
        Show-Urls
    }
    "build" { Assert-Env; Invoke-Compose build cms }
    "down" { Invoke-Compose down }
    "restart" { Assert-Env; Invoke-Compose restart cms; Wait-Healthy; Show-Urls }
    "logs" { & docker compose logs -f --tail 200 @Rest cms }
    "status" {
        & docker compose ps
        & docker compose exec cms supervisorctl status
        & docker compose exec cms ps -eo pid,etime,args --forest
    }
    "shell" { & docker compose exec cms bash }
    "exec" {
        if (-not $Rest) { Fail "用法：.\cms.cmd exec <指令> [參數...]，例如 .\cms.cmd exec cmsAddUser ..." }
        & docker compose exec cms @Rest
        exit $LASTEXITCODE
    }
    "selftest" { & docker compose exec cms cms-sandbox-check; exit $LASTEXITCODE }
    "fulltest" {
        # 官方功能測試：一次性容器 + 獨立的測試資料庫，不影響正式資料
        Assert-Env
        $user = Get-EnvValue "CMS_DB_USER"; if (-not $user) { $user = "cmsuser" }
        $testdb = "cmsdb_fulltest"
        Invoke-Compose exec -T db dropdb -U $user --if-exists $testdb
        Invoke-Compose exec -T db createdb -U $user -O $user $testdb
        # fulltest 服務不掛載正式資料的 volume（見 compose.yaml）
        $testArgs = @("run", "--rm", "-T", "fulltest", "cms-fulltest")
        if ($Rest) { $testArgs += ($Rest -join " ") }
        & docker compose @testArgs
        $code = $LASTEXITCODE
        & docker compose exec -T db dropdb -U $user --if-exists $testdb
        exit $code
    }
    "backup" {
        Assert-Env
        $db = Get-EnvValue "CMS_DB_NAME"; if (-not $db) { $db = "cmsdb" }
        $user = Get-EnvValue "CMS_DB_USER"; if (-not $user) { $user = "cmsuser" }
        $name = "$db-$(Get-Date -Format 'yyyyMMdd-HHmmss').dump"
        New-Item -ItemType Directory -Force backups | Out-Null
        # 直接寫在容器內的 /backups（= 本機 .\backups），避免 PowerShell 重導向破壞二進位檔
        Invoke-Compose exec -T db pg_dump -U $user -d $db -Fc -f "/backups/$name"
        Write-Host "已備份到 backups\$name" -ForegroundColor Green
    }
    "restore" {
        Assert-Env
        if (-not $Rest) { Fail "用法：.\cms.cmd restore <backups 資料夾內的檔名>" }
        $file = Split-Path -Leaf $Rest[0]
        if (-not (Test-Path (Join-Path "backups" $file))) { Fail "找不到 backups\$file" }
        $db = Get-EnvValue "CMS_DB_NAME"; if (-not $db) { $db = "cmsdb" }
        $user = Get-EnvValue "CMS_DB_USER"; if (-not $user) { $user = "cmsuser" }
        $answer = Read-Host "將以 $file 覆蓋目前資料庫 $db（目前資料會消失）。輸入 yes 繼續"
        if ($answer -ne "yes") { Fail "已取消" }
        Invoke-Compose stop cms
        Invoke-Compose exec -T db dropdb -U $user --if-exists $db
        Invoke-Compose exec -T db createdb -U $user -O $user $db
        Invoke-Compose exec -T db pg_restore -U $user -d $db --no-owner "/backups/$file"
        Invoke-Compose start cms
        Wait-Healthy
        Write-Host "還原完成" -ForegroundColor Green
    }
    "save-image" {
        Assert-Env
        $images = (& docker compose config --images) | Where-Object { $_ }
        $out = "cms-images-$(Get-Date -Format 'yyyyMMdd').tar"
        & docker save -o $out @images
        if ($LASTEXITCODE -ne 0) { Fail "docker save 失敗" }
        Write-Host "已匯出 $($images -join ', ') 到 $out" -ForegroundColor Green
        Write-Host "在其他電腦：複製整個資料夾與 $out，執行 .\cms.cmd load-image $out 再 .\cms.cmd init / up"
    }
    "load-image" {
        if (-not $Rest) { Fail "用法：.\cms.cmd load-image <tar 檔>" }
        & docker load -i $Rest[0]
        exit $LASTEXITCODE
    }
    "destroy" {
        $answer = Read-Host "將刪除所有容器與資料（資料庫、提交、日誌），無法復原。輸入 DELETE 繼續"
        if ($answer -ne "DELETE") { Fail "已取消" }
        Invoke-Compose down -v
    }
    default {
        @"
CMS Docker 管理工具

  .\cms.cmd init                 第一次使用：由 .env.example 產生 .env（隨機密碼）
  .\cms.cmd up                   啟動（映像不存在時自動建置；已啟動則套用 .env 變更）
  .\cms.cmd build                重新建置映像（修改 docker\ 內檔案或版本後）
  .\cms.cmd down                 停止並移除容器（資料保留在 volume）
  .\cms.cmd restart              重新啟動 CMS 容器
  .\cms.cmd status               容器、服務、行程狀態
  .\cms.cmd logs                 即時日誌（Ctrl+C 離開）
  .\cms.cmd shell                進入容器（可直接使用 cmsAddUser 等所有 CMS 指令）
  .\cms.cmd exec <指令...>       在容器內執行單一 CMS 指令
  .\cms.cmd selftest             重新檢查 isolate 沙箱（數秒）
  .\cms.cmd fulltest             執行 CMS 官方功能測試，驗證完整評測流程（數分鐘）
  .\cms.cmd backup               備份資料庫到 backups\
  .\cms.cmd restore <檔名>       從 backups\ 還原資料庫
  .\cms.cmd save-image           匯出映像檔（離線 / 其他電腦部署）
  .\cms.cmd load-image <tar>     匯入映像檔
  .\cms.cmd destroy              刪除所有容器與資料
"@ | Write-Host
    }
}
