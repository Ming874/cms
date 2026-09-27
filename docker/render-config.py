#!/opt/cms-venv/bin/python
"""依環境變數產生 /usr/local/etc/cms.conf 與 cms.ranking.conf。

以 CMS 官方的 cms.conf.sample 為基底，只覆寫需要調整的欄位；
若 /etc/cms-docker/cms.override.json 存在，最後再合併進去（進階用）。
"""

import json
import os
import re
import secrets
import sys
from urllib.parse import quote

SAMPLE_DIR = "/opt/cms-docker"
OVERRIDE_DIR = "/etc/cms-docker"
CMS_CONF = "/usr/local/etc/cms.conf"
RANKING_CONF = "/usr/local/etc/cms.ranking.conf"
SECRET_FILE = "/var/local/lib/cms/.secret_key"


def env(name, default=None, required=False):
    value = os.environ.get(name, "")
    if value == "":
        if required:
            sys.exit(f"[cms-render-config] 缺少環境變數 {name}")
        return default
    return value


def env_int(name, default, minimum=0):
    raw = env(name, str(default))
    try:
        value = int(raw)
    except ValueError:
        sys.exit(f"[cms-render-config] {name} 必須是整數，目前是 {raw!r}")
    if value < minimum:
        sys.exit(f"[cms-render-config] {name} 不可小於 {minimum}")
    return value


def load_sample(name):
    # 樣板中有大量重複的 "_help" 鍵（當註解用），json 會保留最後一個，無妨。
    with open(os.path.join(SAMPLE_DIR, name), encoding="utf-8") as f:
        return json.load(f)


def deep_merge(base, extra):
    for key, value in extra.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            deep_merge(base[key], value)
        else:
            base[key] = value


def apply_override(conf, name):
    path = os.path.join(OVERRIDE_DIR, name)
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            deep_merge(conf, json.load(f))
        print(f"[cms-render-config] 已套用覆寫設定 {path}")


def secret_key():
    key = env("CMS_SECRET_KEY")
    if key is None and os.path.isfile(SECRET_FILE):
        with open(SECRET_FILE, encoding="utf-8") as f:
            key = f.read().strip()
    if key is None:
        # 第一次啟動時產生，存在資料 volume 中，之後重啟沿用（登入 cookie 才不會失效）
        key = secrets.token_hex(16)
        with open(SECRET_FILE, "w", encoding="utf-8") as f:
            f.write(key + "\n")
        os.chmod(SECRET_FILE, 0o600)
    if not re.fullmatch(r"[0-9a-fA-F]{32}", key):
        sys.exit("[cms-render-config] CMS_SECRET_KEY 必須是 32 個十六進位字元")
    return key.lower()


def write_json(path, data):
    # 目的檔由 prerequisites.py 建立並屬於 cmsuser，直接覆寫內容
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4, ensure_ascii=False)
        f.write("\n")


def main():
    db_url = "postgresql+psycopg2://{user}:{password}@{host}:{port}/{name}".format(
        user=quote(env("CMS_DB_USER", "cmsuser"), safe=""),
        password=quote(env("CMS_DB_PASSWORD", required=True), safe=""),
        host=env("CMS_DB_HOST", "db"),
        port=env_int("CMS_DB_PORT", 5432, 1),
        name=quote(env("CMS_DB_NAME", "cmsdb"), safe=""),
    )
    workers = env_int("CMS_WORKERS", 4, 1)
    proxies = env_int("CMS_NUM_PROXIES", 0)
    rws_user = env("CMS_RANKING_USERNAME", "ranking")
    rws_password = env("CMS_RANKING_PASSWORD", required=True)

    conf = load_sample("cms.conf.sample")
    conf["database"] = db_url
    conf["secret_key"] = secret_key()
    conf["core_services"]["Worker"] = [["localhost", 26000 + i] for i in range(workers)]
    conf["contest_listen_address"] = [""]
    conf["contest_listen_port"] = [8888]
    conf["admin_listen_address"] = ""
    conf["admin_listen_port"] = 8889
    conf["num_proxies_used"] = proxies
    conf["admin_num_proxies_used"] = proxies
    conf["rankings"] = [
        "http://{}:{}@127.0.0.1:8890/".format(quote(rws_user, safe=""), quote(rws_password, safe=""))
    ]
    conf["docs_path"] = "/usr/share/cms/docs"
    conf["max_submission_length"] = env_int("CMS_MAX_SUBMISSION_LENGTH", conf["max_submission_length"], 1)
    conf["max_input_length"] = env_int("CMS_MAX_INPUT_LENGTH", conf["max_input_length"], 1)
    apply_override(conf, "cms.override.json")
    write_json(CMS_CONF, conf)

    ranking = load_sample("cms.ranking.conf.sample")
    ranking["bind_address"] = ""
    ranking["http_port"] = 8890
    ranking["username"] = rws_user
    ranking["password"] = rws_password
    apply_override(ranking, "cms.ranking.override.json")
    write_json(RANKING_CONF, ranking)

    print(f"[cms-render-config] 設定完成：Worker x{workers}，資料庫 {env('CMS_DB_HOST', 'db')}")


if __name__ == "__main__":
    main()
