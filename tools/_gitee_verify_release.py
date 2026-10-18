# -*- coding: utf-8 -*-
"""校验 Gitee Release v0.3.2：附件清单 + 中文 body 无 U+FFFD 乱码。"""
import json
import os
import urllib.request

TOKEN = os.environ["GITEE_TOKEN"]
RELEASE_ID = "1215505"
OWNER, REPO = "zrocks", "my_schedule_app"

opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
with opener.open(f"https://gitee.com/api/v5/repos/{OWNER}/{REPO}/releases/{RELEASE_ID}?access_token={TOKEN}") as r:
    rel = json.loads(r.read().decode("utf-8"))

body = rel.get("body", "")
print("name:", rel.get("name"))
print("tag:", rel.get("tag_name"), "| target_commitish:", rel.get("target_commitish"))
print("assets count:", len(rel.get("assets", [])))
for a in rel.get("assets", []):
    print(f"  - {a['name']}  {a.get('size', 0)} bytes  {a.get('browser_download_url','')}")
print("REPLACEMENT_CHAR_IN_BODY:", "\ufffd" in body)
print("BODY_HEAD:", body.splitlines()[0] if body else "(empty)")
