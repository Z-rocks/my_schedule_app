# -*- coding: utf-8 -*-
"""向已创建的 Gitee Release 上传 APK 附件。

用法：GITEE_TOKEN=... GITEE_RELEASE_ID=... python gitee_upload_assets.py
- multipart 字段名必须是 `file`（Gitee attach_files 接口约定）
- 令牌走 access_token 查询参数，不走 Bearer 头
- 直连，绕过沙箱代理
"""
import json
import os
import sys
import urllib.request
import uuid

TOKEN = os.environ["GITEE_TOKEN"]
RELEASE_ID = os.environ["GITEE_RELEASE_ID"]
OWNER, REPO = "zrocks", "my_schedule_app"
# v0.3.4 起由 tools/build_release_apks.sh 产出（逐 ABI 构建，统一 versionCode）。
# 老目录 build/app/outputs/flutter-apk 只作为回落，避免旧流程下脚本跑不动。
APK_DIR = "build/release-apks"
if not os.path.isdir(APK_DIR):
    APK_DIR = "build/app/outputs/flutter-apk"

# 上传顺序：通用包优先，再分架构包（与 v0.3.1 保持一致）
FILES = [
    "app-release.apk",
    "app-arm64-v8a-release.apk",
    "app-armeabi-v7a-release.apk",
    "app-x86_64-release.apk",
]


def upload(path):
    boundary = uuid.uuid4().hex
    filename = os.path.basename(path)
    with open(path, "rb") as f:
        payload = f.read()
    body = b"".join([
        b"--", boundary.encode(), b"\r\n",
        b'Content-Disposition: form-data; name="file"; filename="',
        filename.encode(), b'"\r\n',
        b"Content-Type: application/vnd.android.package-archive\r\n\r\n",
        payload, b"\r\n",
        b"--", boundary.encode(), b"--\r\n",
    ])
    url = (f"https://gitee.com/api/v5/repos/{OWNER}/{REPO}"
           f"/releases/{RELEASE_ID}/attach_files?access_token={TOKEN}")
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type",
                   f"multipart/form-data; boundary={boundary}")
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(req) as resp:
        return json.loads(resp.read().decode("utf-8"))


for name in FILES:
    path = os.path.join(APK_DIR, name)
    r = upload(path)
    print(f"OK {name} ({os.path.getsize(path)} bytes) -> {r.get('browser_download_url', '')}")
