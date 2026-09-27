# 進階設定覆寫（選用）

一般設定請改專案根目錄的 `.env`。若需要調整 `.env` 沒有提供的 CMS 設定，
在這個資料夾放入下列檔案，內容會在容器啟動時**合併**到自動產生的設定檔上：

| 檔名 | 合併到 |
|---|---|
| `cms.override.json` | `/usr/local/etc/cms.conf` |
| `cms.ranking.override.json` | `/usr/local/etc/cms.ranking.conf` |

欄位說明請參考 CMS 官方的 `cms.conf.sample`（容器內 `/opt/cms-docker/cms.conf.sample`）。

範例 `cms.override.json`：

```json
{
    "cookie_duration": 21600,
    "max_submission_length": 200000,
    "submit_local_copy": true
}
```

修改後執行 `.\cms.cmd restart`（或 `./cms.sh restart`）生效。
