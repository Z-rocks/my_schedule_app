# -*- coding: utf-8 -*-
"""创建 Gitee Release。

用法：
    VERSION=0.3.3 GITEE_TOKEN=... python tools/gitee_release.py

约定：
- Release 说明放在 `tools/release_notes/v<VERSION>.md`（UTF-8，可自由写中文）
- **中文绝不能走 shell 传参**：Git Bash 按 GBK 传，Gitee 按 UTF-8 解，会全变 U+FFFD。
  这里用 urllib.parse.urlencode(..., encoding='utf-8') 编码，与 shell 无关。
- `target_commitish` 必填，缺了会 400。
- 令牌走 access_token 查询参数（wincred 里存的是账号密码，不是 PAT，走 header 会 401）。
- 直连不走系统代理：沙箱代理对 gitee API 有干扰。
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

TOKEN = os.environ["GITEE_TOKEN"]
VERSION = os.environ["VERSION"].lstrip("v")
OWNER, REPO = "zrocks", "my_schedule_app"
API = "https://gitee.com/api/v5"

HERE = os.path.dirname(os.path.abspath(__file__))
NOTES = os.path.join(HERE, "release_notes", f"v{VERSION}.md")
if not os.path.exists(NOTES):
    sys.exit(f"缺少 Release 说明文件：{NOTES}")
with open(NOTES, encoding="utf-8") as f:
    BODY = f.read()


def api(method, path, fields=None, raw=None, content_type=None):
    url = f"{API}{path}?access_token={TOKEN}"
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    if raw is not None:
        data = raw
    elif fields is not None:
        data = urllib.parse.urlencode(fields, encoding="utf-8").encode("utf-8")
    else:
        data = None
    req = urllib.request.Request(url, data=data, method=method)
    if content_type:
        req.add_header("Content-Type", content_type)
    with opener.open(req) as resp:
        return json.loads(resp.read().decode("utf-8"))


try:
    rel = api("POST", f"/repos/{OWNER}/{REPO}/releases",
              fields={"tag_name": f"v{VERSION}",
                      "name": f"校园助手 v{VERSION}",
                      "body": BODY,
                      "target_commitish": "main"})
except urllib.error.HTTPError as e:
    print(f"HTTP {e.code}: {e.read().decode('utf-8', 'replace')}")
    # 400 常见原因：该 tag 已有 Release。列出来看看
    existing = api("GET", f"/repos/{OWNER}/{REPO}/releases")
    for r in existing:
        if r.get("tag_name") == f"v{VERSION}":
            print(f"EXISTING id={r['id']} name={r.get('name')} url={r.get('html_url')}")
    sys.exit(1)
print("RELEASE_ID=" + str(rel["id"]))
print("RELEASE_URL=" + rel.get("html_url", ""))
