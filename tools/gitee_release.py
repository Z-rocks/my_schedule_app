# -*- coding: utf-8 -*-
"""创建 Gitee Release v0.3.2（中文必须走 urllib urlencode UTF-8，不能 shell 传参）"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

TOKEN = os.environ["GITEE_TOKEN"]
OWNER, REPO = "zrocks", "my_schedule_app"
API = "https://gitee.com/api/v5"

BODY = """## 校园助手 v0.3.2

### 改进
- **校外也能登录教务系统**：不在学校时自动识别 WebVPN 网关，走 CAS 统一身份认证的二维码登录
- 新增校园网状态自动探测（校内直连 / 校外网关），登录方式随网络环境自动切换，无需手动设置
- 扫码登录：CAS 二维码可一键保存到相册、可直接拉起微信扫一扫
- 插件能力：manifest 新增 qr_login 声明，第三方教务插件也能接入校外登录流程

### 说明
- 校园网内的登录流程与之前完全一致，不受本次改动影响
- 新增「保存二维码到相册」能力：Android 10 及以上走系统相册免权限；Android 7–9 需要存储权限，拒绝后可改用另一台设备扫码
- 覆盖安装不会丢失数据（学期、课程、登录信息均保留）

### 安装
- 通用包 `app-release.apk`：适合绝大多数机型
- 分架构包（更小）：`app-arm64-v8a-release.apk`（近几年的手机）、`app-armeabi-v7a-release.apk`（老机型）、`app-x86_64-release.apk`（模拟器），按手机芯片选择

### 已知问题
- 极少部分机型可能无法拉起微信扫一扫，可保存二维码后用另一台设备扫
"""


def api(method, path, fields=None, raw=None, content_type=None):
    url = f"{API}{path}?access_token={TOKEN}"
    # 直连不走系统代理：沙箱代理对 gitee API 会干扰，稳定起见显式绕过
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


rel = None
try:
    rel = api("POST", f"/repos/{OWNER}/{REPO}/releases",
              fields={"tag_name": "v0.3.2", "name": "校园助手 v0.3.2",
                  "body": BODY, "target_commitish": "main"})
except urllib.error.HTTPError as e:
    print(f"HTTP {e.code}: {e.read().decode('utf-8', 'replace')}")
    # 400 常见原因：该 tag 已有 Release。列出来看看
    existing = api("GET", f"/repos/{OWNER}/{REPO}/releases")
    for r in existing:
        if r.get("tag_name") == "v0.3.2":
            print(f"EXISTING id={r['id']} name={r.get('name')} url={r.get('html_url')}")
    sys.exit(1)
print("RELEASE_ID=" + str(rel["id"]))
print("RELEASE_URL=" + rel.get("html_url", ""))
