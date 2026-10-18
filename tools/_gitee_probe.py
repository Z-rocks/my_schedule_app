# -*- coding: utf-8 -*-
"""诊断：直连（不走代理）调用 Gitee API，获取当前用户信息，只打印 id/username。"""
import json
import os
import urllib.request

TOKEN = os.environ["GITEE_TOKEN"]
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

req = urllib.request.Request(
    f"https://gitee.com/api/v5/user?access_token={TOKEN}", method="GET")
with opener.open(req) as resp:
    data = json.loads(resp.read().decode("utf-8"))
print("OK id=%s login=%s name=%s" % (data.get("id"), data.get("login"), data.get("name")))
