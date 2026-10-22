# -*- coding: utf-8 -*-
"""把已发布 Release 的正文替换成 tools/release_notes/v<VERSION>.md 的内容。

用法：VERSION=0.5.1 RELEASE_ID=1228681 GITEE_TOKEN=... python patch_body.py
中文一律走 urlencode(encoding='utf-8')，不经 shell 传参。
"""
import os
import urllib.parse
import urllib.request

TOKEN = os.environ["GITEE_TOKEN"]
VERSION = os.environ["VERSION"].lstrip("v")
RELEASE_ID = os.environ["GITEE_RELEASE_ID"]
API = "https://gitee.com/api/v5/repos/zrocks/my_schedule_app/releases"

here = os.path.dirname(os.path.abspath(__file__))
notes = os.path.join(here, "release_notes", f"v{VERSION}.md")
with open(notes, encoding="utf-8") as f:
    body = f.read()

data = urllib.parse.urlencode(
    {
        "access_token": TOKEN,
        # Gitee 的 PATCH 是"整体替换"语义：name 缺了直接 400 "name is missing"，
        # 跟仓库 PATCH 必须同时带 name+path 是同一个坑。
        "name": f"校园助手 v{VERSION}",
        "tag_name": f"v{VERSION}",
        "body": body,
    },
    encoding="utf-8",
).encode("utf-8")
req = urllib.request.Request(
    f"{API}/{RELEASE_ID}", data=data, method="PATCH",
    headers={"Content-Type": "application/x-www-form-urlencoded"},
)
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
try:
    with opener.open(req, timeout=60) as r:
        import json
        d = json.load(r)
    print("tag:", d.get("tag_name"), "| body has FFFD:", "\ufffd" in (d.get("body") or ""))
    print("body head:", (d.get("body") or "")[:40].replace("\n", " | "))
except urllib.error.HTTPError as e:
    print("HTTP", e.code)
    print(e.read().decode("utf-8", "replace")[:500])
    raise
