# -*- coding: utf-8 -*-
"""发版前预检 Gitee 仓库附件配额。

用法：
    GITEE_TOKEN=... python tools/gitee_quota.py

为什么需要它：Gitee 的 **仓库级** 附件配额只有 1 GB，所有 Release 的附件
共享这一份额度（源码 zip/tar.gz 是 Gitee 自动生成的，不占额度）。
本项目单版 4 个包约 126 MB → 1 GB 只够 8 个版本。

v0.7.0 发版时就是撞在这里：前 8 个版本占满 1004.5 MB，传到第二个包才报
`400 验证失败：文件大小已超出仓库附件配额：1 GB`，而通用包（58.9 MB）
已经传上去了，状态是半残的。**先预检，别等传一半失败。**

清理办法（删附件不删 Release，tag 和文字说明都保留）：
    DELETE /repos/{owner}/{repo}/releases/{release_id}/attach_files/{file_id}
附件 id 要从 `GET /repos/{o}/{r}/releases/{id}/attach_files` 拿
（`GET /releases` 列表里的 assets 只给 name 和下载地址，没有 id 和 size）。
"""
import json
import os
import sys
import urllib.parse
import urllib.request

TOKEN = os.environ["GITEE_TOKEN"]
OWNER, REPO = "zrocks", "my_schedule_app"
API = "https://gitee.com/api/v5"
QUOTA_MB = 1024.0

# 与 gitee_upload_assets.py 一致：以脚本自身位置定锚，不看当前工作目录
# （本机有两个 checkout 各有自己的 build/release-apks，用相对路径会读错）。
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCAL_APK_DIR = os.path.join(REPO_ROOT, "build", "release-apks")
LOCAL_FILES = [
    "app-release.apk",
    "app-arm64-v8a-release.apk",
    "app-armeabi-v7a-release.apk",
    "app-x86_64-release.apk",
]


def api(path):
    url = f"{API}{path}{'&' if '?' in path else '?'}access_token={TOKEN}"
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(url) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main():
    releases = api(f"/repos/{OWNER}/{REPO}/releases")
    rows = []
    total = 0
    for r in sorted(releases, key=lambda x: x.get("created_at") or ""):
        files = api(f"/repos/{OWNER}/{REPO}/releases/{r['id']}/attach_files")
        size = sum(f.get("size") or 0 for f in files)
        total += size
        rows.append((r["tag_name"], len(files), size))

    print(f"{'版本':10} {'附件数':>4}  {'占用':>10}")
    for tag, count, size in rows:
        print(f"{tag:10} {count:>4}  {size / 1048576:9.1f} MB")

    used = total / 1048576
    left = QUOTA_MB - used
    print(f"\n合计 {used:.1f} MB / {QUOTA_MB:.0f} MB，剩余 {left:.1f} MB")

    need = 0
    if os.path.isdir(LOCAL_APK_DIR):
        for name in LOCAL_FILES:
            path = os.path.join(LOCAL_APK_DIR, name)
            if os.path.exists(path):
                need += os.path.getsize(path)
        print(f"本次要传 {need / 1048576:.1f} MB（{LOCAL_APK_DIR}）")
    else:
        print(f"（没找到 {LOCAL_APK_DIR}，跳过本次估算；先跑 tools/build_release_apks.sh）")

    if need and need > left * 1048576:
        short = (need / 1048576) - left
        print(f"\n[不足] 还差 {short:.1f} MB，需要先删旧版本的附件。")
        print("       建议从最早的版本开始删，保留最近 3~4 个版本的完整 4 包。")
        return 1

    print("\n[够用] 可以上传。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
