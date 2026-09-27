# CMS（IOI 評測系統）Docker 部署

在任何裝有 Docker 的電腦上，用兩個指令就能架好一套 **CMS v1.5**（IOI Contest Management System），
環境內容對應實驗室的安裝文件（Ubuntu 24.04、Python 3.12、g++/gcc、OpenJDK 11、Free Pascal、PostgreSQL），
而且所有版本都已鎖定，換電腦、重建、離線部署都會得到相同的環境。

> 這裡的 CMS 指的是 IOI 的 Contest Management System，不是內容管理系統。

---

## 快速開始

**需求**：Windows 10/11 + [Docker Desktop](https://www.docker.com/products/docker-desktop/)（WSL 2 後端），
或 Linux + Docker Engine 24 以上（需 cgroup v2：Ubuntu 22.04+、Debian 11+ 等）。建議 4 GB 以上記憶體。

### Windows（命令提示字元或 PowerShell 都可以）

```bat
cd C:\GitHub\cms
.\cms.cmd init      # 產生 .env，自動填入隨機密碼，並顯示管理員密碼
.\cms.cmd up        # 第一次會建置映像（約 5–10 分鐘），之後幾秒內啟動
```

> 請打 `.\cms.cmd`，**不要**直接打 `.\cms.ps1`：在命令提示字元裡 `.ps1` 會被記事本打開而不是執行，
> 在 PowerShell 裡則可能被「已停用指令碼執行」擋下。`cms.cmd` 會用正確的方式呼叫 `cms.ps1`。

### Linux / macOS / WSL

```bash
./cms.sh init
./cms.sh up
```

### 啟動後

| 介面 | 網址 | 用途 |
|---|---|---|
| 管理介面 AdminWebServer | http://localhost:8889 | 建立考場、題目、使用者（帳號 `admin`，密碼在 `.env` 的 `CMS_ADMIN_PASSWORD`） |
| 考生介面 ContestWebServer | http://localhost:8888 | 考生登入、提交程式碼 |
| 排名介面 RankingWebServer | http://localhost:8890 | 預設關閉，見「考場模式」 |

建立流程與原本相同：在管理介面先 **Create new contest / task / user**，再到考場頁面把題目與使用者加入。
**建立考場後不需要重啟任何服務**，考生重新整理 http://localhost:8888 就能看到新考場。

---

## 日常操作

| 指令（Windows 用 `.\cms.cmd`，Linux 用 `./cms.sh`） | 說明 |
|---|---|
| `init` | 第一次使用：產生 `.env`（隨機密碼） |
| `up` | 啟動；修改 `.env` 後再執行一次即可套用 |
| `down` | 停止並移除容器（**資料保留**） |
| `restart` | 重新啟動 CMS |
| `status` | 容器、服務、行程狀態 |
| `logs` | 即時日誌（所有 CMS 服務的日誌都會集中在這裡） |
| `shell` | 進入容器，所有 `cms*` 指令都可以直接使用 |
| `exec <指令>` | 在容器內執行單一指令 |
| `selftest` | 重新檢查 isolate 沙箱（數秒） |
| `fulltest` | 執行 CMS 官方功能測試，驗證完整評測流程（數分鐘，不影響正式資料） |
| `backup` / `restore <檔名>` | 備份 / 還原資料庫（`backups\` 資料夾） |
| `build` | 重新建置映像（改了 `docker\` 內的檔案或版本時） |
| `save-image` / `load-image <tar>` | 匯出 / 匯入映像檔，用於離線或其他電腦 |
| `destroy` | 刪除所有容器與資料（無法復原） |

### 原文件指令對照

| 原本（VM / 實體機） | Docker 版 |
|---|---|
| `source ~/cms_venv/bin/activate`、`cd ~/cms_venv/bin` | 不需要；`shell` 進去後直接打指令 |
| `cmsInitDB` | 第一次啟動時自動執行 |
| `cmsAddAdmin -p PASSWORD NAME` | `.\cms.cmd exec cmsAddAdmin -p PASSWORD NAME` |
| `cmsAdminWebServer`、`cmsResourceService -a` | 已自動啟動並常駐，服務當掉會自動重啟 |
| `cmsLogService` | 已自動啟動；看日誌用 `logs`，檔案在容器內 `/var/local/log/cms` |
| `cmsRankingWebServer` | `.env` 設 `CMS_RANKING=true` 後 `up` |
| `cmsDumpExporter` | `.\cms.cmd exec cmsDumpExporter /backups/匯出.tar.gz` |
| `cmsDumpImporter 檔案` | 見「從舊的 CMS 搬資料過來」 |
| 考試結束 Ctrl+C 關伺服器 | `down`（資料保留），或讓它一直開著 |

### 批次新增使用者（原文件的 for 迴圈）

```powershell
.\cms.cmd shell
```
進入容器後照原本的寫法即可：
```bash
for i in {1..10}; do
    cmsAddUser "first_name_$i" "last_name_$i" "user_name_$i" -p "password_$i"
    cmsAddParticipation -c 1 "user_name_$i"
done
```

---

## 考場模式

`.env` 的 `CMS_CONTEST_ID` 決定服務要載入哪個考場：

| 設定 | 行為 | 適用 |
|---|---|---|
| `ALL`（預設） | 同時服務所有考場。考生在首頁選擇考場；新增考場**不必重啟**。 | 平常上課、練習 |
| 考場 ID（例如 `1`） | 只服務該考場，首頁直接是該考場；並啟動 ProxyService 把成績送到排名網站。 | 正式比賽、需要排名看板 |

要使用排名網站：設定 `CMS_CONTEST_ID=<考場ID>`、`CMS_RANKING=true`，再執行 `up`。
（CMS 的 ProxyService 必須指定考場，所以 `ALL` 模式下排名網站收不到成績。）

---

## 設定（`.env`）

| 變數 | 預設 | 說明 |
|---|---|---|
| `CMS_WORKERS` | `4` | 同時評測的數量。建議 ≤ 實體核心數的一半，執行時間才量得穩定 |
| `CWS_BIND` / `CWS_PORT` | `0.0.0.0` / `8888` | 考生介面；`0.0.0.0` 讓區網的學生可以連線 |
| `AWS_BIND` / `AWS_PORT` | `127.0.0.1` / `8889` | 管理介面預設只有本機能連；要讓其他電腦管理請改成 `0.0.0.0` |
| `RWS_BIND` / `RWS_PORT` | `0.0.0.0` / `8890` | 排名介面 |
| `CMS_CONTEST_ID` | `ALL` | 見「考場模式」 |
| `CMS_RANKING` | `false` | 是否啟動排名網站 |
| `CMS_NUM_PROXIES` | `0` | 前面有 nginx 等反向代理時設 `1` |
| `CMS_LOG_RETENTION_DAYS` | `30` | 自動清理超過天數的 CMS 日誌檔 |
| `JDK_PACKAGE` | `openjdk-11-jdk-headless` | Java 版本（改完需 `build`） |
| `EXTRA_LANGS` | `false` | `true` 時額外安裝 PyPy3、PHP、Rust、Haskell、C#（改完需 `build`） |

`.env` 沒提供的 CMS 設定（例如 cookie 時間、提交大小上限）可以用 `config\cms.override.json` 覆寫，見 [config/README.md](config/README.md)。

> 管理介面的語言清單會列出 CMS 支援的所有語言，但映像預設只裝 **C / C++ / Java / Pascal / Python 3**。
> 考場只勾選這幾種；若要開放其他語言，請設定 `EXTRA_LANGS=true` 並重新 `build`。

---

## 備份、還原與搬移

### 資料放在哪裡

| Docker volume | 內容 |
|---|---|
| `cms_pgdata` | PostgreSQL 資料庫（考場、題目、測資、提交，全部都在這裡） |
| `cms_cms-data` | 提交的本機副本、排名網站資料、cookie 金鑰 |
| `cms_cms-log` | 各服務日誌 |
| `.\backups`（本機資料夾） | 備份檔 |

`down`、`restart`、重開機、重建映像都**不會**動到上述資料，只有 `destroy` 會刪除。

### 資料庫備份 / 還原（完整、最快）

```powershell
.\cms.cmd backup                              # → backups\cmsdb-20260924-153000.dump
.\cms.cmd restore cmsdb-20260924-153000.dump  # 會先要求輸入 yes 確認
```
這是完整的 PostgreSQL 備份（`pg_dump -Fc`），適合同一版 CMS 之間使用。**正式比賽前後都建議備份一次。**

### 從舊的 CMS（實驗室 VM）搬資料過來

CMS 自己的匯出格式可以跨機器、跨版本使用：

1. 在舊機器（已啟用 venv）：`cmsDumpExporter old-cms.tar.gz`
2. 把檔案複製到這個專案的 `backups\` 資料夾
3. 匯入（`-d` 會先**清空**目前的資料庫）：
   ```powershell
   .\cms.cmd exec cmsDumpImporter -d /backups/old-cms.tar.gz
   .\cms.cmd restart
   ```

### 複製到其他電腦 / 沒有網路的考場

```powershell
.\cms.cmd save-image          # 產生 cms-images-YYYYMMDD.tar（含 CMS 與 PostgreSQL 映像）
```
把整個專案資料夾（**不含** `.env` 也可以）連同 tar 檔複製到新電腦，然後：
```powershell
.\cms.cmd load-image cms-images-YYYYMMDD.tar
.\cms.cmd init
.\cms.cmd up                  # 映像已存在，不需要網路也不會重新建置
```
兩台電腦跑的就是**同一個映像**，評測環境完全相同。

---

## 架構

```
 瀏覽器 ─ 8888 考生 ─┐
        ─ 8889 管理 ─┤   ┌──────────────── cms 容器 ──────────────────────────┐
        ─ 8890 排名 ─┴──▶│ tini → supervisord（以 cmsuser 執行）               │
                         │   ├─ LogService                                    │
                         │   ├─ ResourceService -a ALL（自動啟動並監看下列服務）│
                         │   │    ├─ AdminWebServer、ContestWebServer         │
                         │   │    ├─ EvaluationService、ScoringService        │
                         │   │    ├─ Worker × N ──▶ isolate 沙箱（cgroup v2）  │
                         │   │    └─ Checker、PrintingService、ProxyService    │
                         │   └─ RankingWebServer（選用）                      │
                         └───────────────┬────────────────────────────────────┘
                                         │ 5432（只在 Docker 內部網路）
                         ┌───────────────▼──────────────┐
                         │ db 容器：postgres:16          │
                         └──────────────────────────────┘
```

| 檔案 | 作用 |
|---|---|
| [compose.yaml](compose.yaml) | 兩個服務（db、cms）、連接埠、volume、健康檢查 |
| [docker/Dockerfile](docker/Dockerfile) | 映像：系統套件、CMS 原始碼（tag + commit 驗證）、venv、isolate |
| [docker/constraints.txt](docker/constraints.txt) | 所有 Python 套件的確切版本 |
| [docker/entrypoint.sh](docker/entrypoint.sh) | 啟動流程：cgroup → 設定檔 → 等資料庫 → 初始化 → 沙箱自檢 → 啟動服務 |
| [docker/cgroup-setup.sh](docker/cgroup-setup.sh) | 在容器內劃出 isolate 專用的 cgroup 子樹 |
| [docker/render-config.py](docker/render-config.py) | 依 `.env` 產生 `cms.conf`、`cms.ranking.conf` |
| [docker/sandbox-check.sh](docker/sandbox-check.sh) | 沙箱自我檢查（正常 / 超時 / 超記憶體） |
| [docker/supervisord.conf](docker/supervisord.conf) | 容器內的行程管理 |
| [cms.cmd](cms.cmd) / [cms.ps1](cms.ps1) / [cms.sh](cms.sh) | 管理指令（Windows 用 cms.cmd，它會呼叫 cms.ps1；Linux 用 cms.sh） |

---

## 與原安裝文件的差異（為什麼這樣做）

逐步照文件安裝時會遇到的問題，以及這裡的處理方式：

| 原文件的步驟 / 問題 | 原因分析 | 這裡的做法 |
|---|---|---|
| `cmsInitDB` 出現 `No module named 'pkg_resources'`，需要降級 setuptools | Python 3.12 的 venv 預設不含 setuptools；新版 setuptools 已移除 `pkg_resources`，但 CMS 1.5 執行時仍會 import 它（語言、題型外掛與翻譯檔的載入都靠它） | 映像內固定 `setuptools==69.5.1`，所有 Python 套件以 `constraints.txt` 鎖定版本 |
| `python3 setup.py install` | 已被棄用的 egg 安裝方式，和新版 setuptools 容易衝突 | 改用 `pip install .`（上游 v1.5.1 的做法） |
| `prerequisites.py install` 後要 `sudo reboot` 讓群組生效 | 使用者要加入 `cmsuser` 群組才能執行 isolate | 容器從一開始就以 `cmsuser` 執行，不需要重開機 |
| 安裝 `cgroup-lite` | 這是 cgroup v1 時代的工具；CMS 1.5 附的 isolate 2.0 **只支援 cgroup v2** | 不安裝；改由啟動腳本在容器內設定 cgroup v2 |
| 手動 `createuser`、`createdb`、`ALTER SCHEMA`、`GRANT pg_largeobject` | PostgreSQL 15 以後 public schema 權限變嚴，所以要手動授權 | 資料庫在獨立容器中由官方映像建立，`cmsuser` 是這個專用資料庫的擁有者，不需要手動授權；資料庫不對外開放 |
| 手動 `nano /usr/local/etc/cms.conf` 改密碼 | 設定散落、容易打錯 | 每次啟動由 `.env` 自動產生 |
| `cmsResourceService -a` 啟動時要選考場；沒有考場時要先開 AWS 建立、再全部關掉重開 | 單一考場模式的限制 | 預設使用 `-a ALL`（多考場模式），管理介面常駐，新增考場不必重啟 |
| Docker 版文件使用 `master` 分支、`cgroup: host`、資料庫目錄掛在 Windows 資料夾 | master 是尚未發布的 1.6 開發版；`cgroup: host` 會讓 isolate 直接改主機的 cgroup 根目錄；PostgreSQL 放在 Windows 掛載目錄又慢又容易有權限問題 | 使用正式發布版 v1.5.1；容器使用私有 cgroup namespace；資料庫使用 Docker volume |

**版本選擇**：預設使用 **v1.5.1**（2025-06，v1.5 系列的最新修正版）。它和 v1.5.0 的資料庫結構相同（schema version 44），
修正了 EvaluationService 的參數順序錯誤、壓縮檔處理問題，並更新了繁體中文翻譯。
若一定要用 v1.5.0：在 `.env` 設定 `CMS_REF=v1.5.0`、`CMS_COMMIT=c87fea7a6bc50d67325c4499a7a5540556803daf`、`CMS_IMAGE=cms-local:v1.5.0`，
而且 v1.5.0 的 requirements 固定的套件版本不同（例如 gevent 24.11.1），必須依下方「更新 Python 套件鎖定」重新產生 `constraints.txt`，
然後 `build`、`fulltest` 驗證（這個組合沒有預先驗證過）。

### 穩定性設計

- **版本全部鎖定**：Ubuntu 24.04、CMS tag + commit 雜湊驗證、isolate（CMS 附帶的固定版本）、Python 套件（constraints.txt）、PostgreSQL 16。
- **沙箱先自我檢查才開放**：每次啟動會實際測試「正常執行 / CPU 超時 / 記憶體超限」，任一項判定錯誤就拒絕啟動，避免在錯誤的環境下評分。
- **isolate 與主機隔離**：isolate 只在容器自己的 cgroup 子樹（`/sys/fs/cgroup/isolate`）裡運作，不會動到主機；同一台主機跑多套 CMS 也不會互相干擾。
- **三層自動恢復**：CMS 的 ResourceService 會重啟當掉的服務 → supervisord 會重啟 ResourceService / LogService → Docker 的 `restart: unless-stopped` 會重啟整個容器（包含電腦重開機後）。
- **健康檢查**：Docker 會持續檢查管理介面與考生介面是否正常回應。
- **資源與日誌**：PostgreSQL 調高 `max_connections` 與 `shm_size`；Docker 日誌自動輪替；CMS 日誌依天數清理。
- **cookie 金鑰固定**：第一次啟動自動產生並保存，重啟後考生不會被登出。

---

## 疑難排解

**啟動失敗：`sandbox-check 失敗` 或 `cgroup` 相關錯誤**
容器必須以 `privileged: true`、`cgroup: private` 執行（compose.yaml 已設定），主機必須使用 cgroup v2。
Docker Desktop 請更新到新版；Linux 可用 `stat -fc %T /sys/fs/cgroup` 檢查，結果應為 `cgroup2fs`。

**學生連不到 8888**
確認 `.env` 的 `CWS_BIND=0.0.0.0`，並允許 Windows 防火牆讓 Docker Desktop 接受連入連線。
學生要用這台電腦的區網 IP 連線（`ipconfig` 查詢），不是 localhost。

**連接埠被占用或 `An attempt was made to access a socket in a way forbidden`**
Windows 的 Hyper-V 可能保留了該連接埠：`netsh interface ipv4 show excludedportrange protocol=tcp`。
在 `.env` 改用其他 `*_PORT` 後再 `up`。

**比賽前務必確認時間正確**
Docker Desktop 的 WSL 2 虛擬機在電腦睡眠或休眠之後，時鐘可能會跑掉，這會直接影響考試的開始和結束時間。
比賽前執行 `.\cms.cmd exec date`，和 Windows 的時間比對；如果不一致，請重新啟動 Docker Desktop（或執行 `wsl --shutdown`）。

**忘記管理員密碼**
`.\cms.cmd exec cmsAddAdmin -p 新密碼 新帳號` 建立另一個管理員，登入後再修改原帳號。

**要更改資料庫密碼**
`.env` 的 `CMS_DB_PASSWORD` 只在資料庫第一次建立時生效。之後要改的話：
```powershell
docker compose exec db psql -U cmsuser -d cmsdb -c "ALTER USER cmsuser PASSWORD '新密碼'"
```
再把 `.env` 改成相同的新密碼，然後執行 `.\cms.cmd up`。

**`bad interpreter` / `\r` 錯誤**
這代表檔案被轉成了 Windows 換行（CRLF）。本專案的 `.gitattributes` 已強制使用 LF，建置時也會自動修正；
如果是手動複製檔案造成的，請重新 `build`。

---

## 升級與重新鎖定版本

- **升級 CMS 版本**：修改 `.env` 的 `CMS_REF`、`CMS_COMMIT`、`CMS_IMAGE`，然後依序執行 `backup`、`build`、`up`。
  跨大版本（例如升到 1.6）時資料庫結構會改變，要先用 `cmsDumpExporter` 匯出，再用新版的 `cmsDumpUpdater` 和 `cmsDumpImporter` 轉換匯入。
- **更新 Python 套件鎖定**：把 `docker/constraints.txt` 清成只剩註解，執行 `build`，確認功能正常後，執行
  `docker run --rm --entrypoint /opt/cms-venv/bin/pip cms-local:v1.5.1 freeze --all --exclude cms --exclude pip`，
  把輸出寫回 `constraints.txt`。

## 安全注意事項

- CMS 容器必須以 **privileged** 模式執行（isolate 需要建立 namespace 和管理 cgroup），所以它對主機的權限等同 root。
  請只在信任的機器上執行，也不要讓不信任的人取得 Docker 的操作權限。考生的程式碼是在 isolate 沙箱裡執行的。
- 管理介面預設只接受本機連線（`AWS_BIND=127.0.0.1`）。如果要從其他電腦管理，建議透過 VPN 或 SSH tunnel，而不是直接開放給整個區網。
- `.env` 裡有所有密碼，已列在 `.gitignore` 中，**不要提交或外流**。
