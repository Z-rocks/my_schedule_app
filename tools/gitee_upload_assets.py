# -*- coding: utf-8 -*-
"""向已创建的 Gitee Release 上传 APK 附件。

用法：GITEE_TOKEN=... GITEE_RELEASE_ID=... python gitee_upload_assets.py
- multipart 字段名必须是 `file`（Gitee attach_files 接口约定）
- 令牌走 access_token 查询参数，不走 Bearer 头
- 直连，绕过沙箱代理
- **产物目录以脚本自身位置为锚点**，不看当前工作目录（见下方注释）
"""
import json
import os
import sys
import urllib.request
import uuid

TOKEN = os.environ["GITEE_TOKEN"]
RELEASE_ID = os.environ["GITEE_RELEASE_ID"]
OWNER, REPO = "zrocks", "my_schedule_app"

# 锚定到"本脚本所在的这个 checkout"，而不是当前工作目录。
#
# 为什么必须这样：这个仓库在本机有两个 worktree ——
#   E:/python/my_schedule_app（main）和 WorkBuddy 的 main-xxxx（分支）。
# 两者各有自己的 build/release-apks，用相对路径时读的是"当前 cwd 那个"。
# v0.7.0 发版就踩过：在 main 的 checkout 里跑本脚本，实际把 10 月 22 日构建的
# v0.5.0（versionCode 3003）传到了 v0.7.0 的 Release 上，接口不报错、
# 字节数也对得上，只有 aapt 能看出来。用 __file__ 定锚就不会串。
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# v0.3.4 起由 tools/build_release_apks.sh 产出（逐 ABI 构建，统一 versionCode）。
# 老目录 build/app/outputs/flutter-apk 只作为回落，避免旧流程下脚本跑不动。
APK_DIR = os.path.join(REPO_ROOT, "build", "release-apks")
if not os.path.isdir(APK_DIR):
    APK_DIR = os.path.join(REPO_ROOT, "build", "app", "outputs", "flutter-apk")

# 上传顺序：通用包优先，再分架构包（与 v0.3.1 保持一致）
FILES = [
    "app-release.apk",
    "app-arm64-v8a-release.apk",
    "app-armeabi-v7a-release.apk",
    "app-x86_64-release.apk",
]


def warn_if_stale():
    """构建产物比 pubspec.yaml 旧 → 十有八九是上一个版本遗留的包。"""
    pubspec = os.path.join(REPO_ROOT, "pubspec.yaml")
    if not os.path.exists(pubspec):
        return
    pub_mtime = os.path.getmtime(pubspec)
    stale = [
        name for name in FILES
        if os.path.exists(os.path.join(APK_DIR, name))
        and os.path.getmtime(os.path.join(APK_DIR, name)) < pub_mtime
    ]
    if stale:
        sys.exit(
            "拒绝上传：以下 APK 比 pubspec.yaml 还旧，几乎肯定是上个版本的产物：\n  "
            + "\n  ".join(stale)
            + f"\n先跑 bash tools/build_release_apks.sh（目录：{APK_DIR}）"
        )


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


warn_if_stale()
print(f"产物目录：{APK_DIR}")
for name in FILES:
    path = os.path.join(APK_DIR, name)
    r = upload(path)
    print(f"OK {name} ({os.path.getsize(path)} bytes) -> {r.get('browser_download_url', '')}")
