# -*- coding: utf-8 -*-
"""创建 GitHub Release 并上传 APK。

用法：
    GH_TOKEN=... VERSION=0.5.0 python tools/github_release.py

约定（与 gitee_release.py 保持一致）：
- Release 说明放在 `tools/release_notes/v<VERSION>.md`（UTF-8，可自由写中文）
- **中文绝不能走 shell 传参**：Git Bash 按 GBK 传、服务端按 UTF-8 解会变 U+FFFD。
  这里读文件 + `json.dumps(..., ensure_ascii=False).encode('utf-8')`，与 shell 无关。
- 直连不走系统代理：沙箱代理对 GitHub API 有干扰。
- 资产上传走 `uploads.github.com`，字段名 `file`，**二进制直接放 body**（不是 multipart）。
- 已存在的 Release 复用（重跑不会报 already_exists），已存在的同名资产先删再传。
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

TOKEN = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or ""
if not TOKEN:
    sys.exit("缺少 GH_TOKEN（需要 repo 权限的 PAT）")
VERSION = os.environ["VERSION"].lstrip("v")
TAG = f"v{VERSION}"
OWNER, REPO = "Z-rocks", "my_schedule_app"
API = "https://api.github.com"
UPLOAD = "https://uploads.github.com"

HERE = os.path.dirname(os.path.abspath(__file__))
NOTES = os.path.join(HERE, "release_notes", f"v{VERSION}.md")
if not os.path.exists(NOTES):
    sys.exit(f"缺少 Release 说明文件：{NOTES}")
with open(NOTES, encoding="utf-8") as f:
    BODY = f.read()

# 上传顺序：通用包优先，再分架构包（与 Gitee 侧一致）
APK_DIR = os.path.join(os.path.dirname(HERE), "build", "release-apks")
FILES = [
    "app-release.apk",
    "app-arm64-v8a-release.apk",
    "app-armeabi-v7a-release.apk",
    "app-x86_64-release.apk",
]

OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def api(method, url, payload=None, content_type="application/json", raw=None):
    data = raw
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"token {TOKEN}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "my-schedule-release")
    if data is not None:
        req.add_header("Content-Type", content_type)
    try:
        with OPENER.open(req, timeout=180) as resp:
            body = resp.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        sys.exit(f"{method} {url} 失败：HTTP {e.code}\n{detail}")


def ensure_release():
    """拿到（或创建）tag 对应的 Release。"""
    url = f"{API}/repos/{OWNER}/{REPO}/releases/tags/{TAG}"
    try:
        return api("GET", url)
    except SystemExit:
        pass
    created = api(
        "POST",
        f"{API}/repos/{OWNER}/{REPO}/releases",
        {
            "tag_name": TAG,
            "target_commitish": "main",
            "name": TAG,
            "body": BODY,
            "draft": False,
            "prerelease": False,
        },
    )
    print(f"已创建 Release {TAG}（id={created['id']}）")
    return created


def upload(release_id, existing, filename):
    path = os.path.join(APK_DIR, filename)
    if not os.path.exists(path):
        sys.exit(f"缺少产物：{path}")
    # 同名资产先删掉，重跑才不会 422
    for asset in existing:
        if asset.get("name") == filename:
            api("DELETE", f"{API}/repos/{OWNER}/{REPO}/releases/assets/{asset['id']}")
            print(f"  删除旧资产 {filename}")
    with open(path, "rb") as f:
        data = f.read()
    size_mb = len(data) / 1024 / 1024
    q = urllib.parse.urlencode({"name": filename})
    result = api(
        "POST",
        f"{UPLOAD}/repos/{OWNER}/{REPO}/releases/{release_id}/assets?{q}",
        raw=data,
        content_type="application/vnd.android.package-archive",
    )
    print(f"  已上传 {filename}（{size_mb:.1f} MB）→ {result.get('browser_download_url')}")


def main():
    release = ensure_release()
    existing = release.get("assets") or []
    print(f"Release {TAG}：现有 {len(existing)} 个资产，开始上传…")
    for name in FILES:
        upload(release["id"], existing, name)
    print(f"\n完成：https://github.com/{OWNER}/{REPO}/releases/tag/{TAG}")


if __name__ == "__main__":
    main()
