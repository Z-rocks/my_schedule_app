# -*- coding: utf-8 -*-
"""没有 Mac 也能出 iOS 包：用 GitHub API 推代码 + 触发 macOS 构建 + 取回 ipa。

背景：本机 `git push` 到 github.com 的 443 不通（代理 502 / TLS 断），
但 `api.github.com` 通。所以这里全部走 Git Data API，不碰 git 传输。

用法（GITHUB_TOKEN 需要 repo + workflow 权限）：
    GITHUB_TOKEN=... python tools/gh_ios_build.py push      # 把本地 main 推到 GitHub
    GITHUB_TOKEN=... python tools/gh_ios_build.py run       # 触发 iOS Build（未签名）
    GITHUB_TOKEN=... python tools/gh_ios_build.py status    # 看最近一次运行
    GITHUB_TOKEN=... python tools/gh_ios_build.py download  # 下载未签名 ipa 到 build/ios/ipa

设计要点：
- **只传改动的文件**：以 GitHub 当前 main 的 tree 为 base_tree，逐个 blob 上传
  `git diff --name-only <远端sha> HEAD` 列出的文件，避免几百次 API 调用。
- 远端 main 不是本地 HEAD 的祖先时直接报错退出（说明有人往 GitHub 推过东西，
  需要人工合并），不做强制覆盖。
- 提交作者沿用仓库既有身份（zys1101）。
- 任何一步失败都打印 GitHub 的原始错误，方便照着排查。
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

TOKEN = os.environ.get("GITHUB_TOKEN", "").strip()
OWNER, REPO = "Z-rocks", "my_schedule_app"
API = "https://api.github.com"
BRANCH = "main"
WORKFLOW_FILE = "ios.yml"
ARTIFACT_NAME = "ios-unsigned-ipa"
OUT_DIR = os.path.join("build", "ios", "ipa")

# 与仓库既有提交保持一致（见 git log）
AUTHOR = {"name": "zys1101", "email": "zys1101@user.noreply.gitee.com"}


def api(method, path, payload=None, raw=None, accept="application/vnd.github+json"):
    url = f"{API}{path}"
    data = None
    headers = {
        "Authorization": f"Bearer {TOKEN}",
        "Accept": accept,
        "User-Agent": "my-schedule-app-ios-build",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if raw is not None:
        data = raw
    elif payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(req, timeout=60) as r:
            body = r.read()
            if accept.endswith("json") or not body:
                return json.loads(body.decode()) if body else None
            return body
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:500]
        sys.exit(f"[GitHub] {method} {path} -> HTTP {e.code}\n{detail}")
    except urllib.error.URLError as e:
        sys.exit(f"[GitHub] 连不上 api.github.com：{e.reason}")


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout.strip()


def remote_head():
    """GitHub 当前 main 的 sha（分支不存在返回 None）。"""
    try:
        return api("GET", f"/repos/{OWNER}/{REPO}/git/ref/heads/{BRANCH}")["object"]["sha"]
    except SystemExit:
        return None


def push():
    local = git("rev-parse", "HEAD")
    remote = remote_head()
    if remote == local:
        print(f"[push] 已是最新（{local[:8]}），无需推送")
        return local
    if remote:
        # 远端必须是本地的祖先，否则拒绝覆盖
        anc = subprocess.run(["git", "merge-base", "--is-ancestor", remote, local])
        if anc.returncode != 0:
            sys.exit(
                f"[push] 远端 main（{remote[:8]}）不是本地 HEAD（{local[:8]}）的祖先，"
                "说明 GitHub 上有本地没有的提交，先人工同步再跑"
            )
        changed = git("diff", "--name-only", remote, local).splitlines()
        msg = git("log", "-1", "--pretty=%B").strip()
        parents = [remote]
    else:
        changed = git("ls-files").splitlines()
        msg = git("log", "-1", "--pretty=%B").strip()
        parents = []

    print(f"[push] 需要上传 {len(changed)} 个文件")
    tree = []
    for path in changed:
        full = os.path.join(".", path)
        if not os.path.exists(full):
            # 删除的文件：tree 里给 null 即删除
            tree.append({"path": path, "mode": "100644", "type": "blob", "sha": None})
            print(f"  - 删除 {path}")
            continue
        with open(full, "rb") as f:
            content = f.read()
        blob = api(
            "POST",
            f"/repos/{OWNER}/{REPO}/git/blobs",
            {"content": base64.b64encode(content).decode(), "encoding": "base64"},
        )
        mode = "100755" if os.access(full, os.X_OK) else "100644"
        tree.append({"path": path, "mode": mode, "type": "blob", "sha": blob["sha"]})
        print(f"  + {path} ({len(content)} B)")

    base_tree = None
    if remote:
        base_tree = api("GET", f"/repos/{OWNER}/{REPO}/git/commits/{remote}")["tree"]["sha"]

    new_tree = api(
        "POST",
        f"/repos/{OWNER}/{REPO}/git/trees",
        {"tree": tree, **({"base_tree": base_tree} if base_tree else {})},
    )
    commit = api(
        "POST",
        f"/repos/{OWNER}/{REPO}/git/commits",
        {"message": msg, "tree": new_tree["sha"], "parents": parents, "author": AUTHOR},
    )
    if remote:
        api("PATCH", f"/repos/{OWNER}/{REPO}/git/refs/heads/{BRANCH}", {"sha": commit["sha"]})
    else:
        api(
            "POST",
            f"/repos/{OWNER}/{REPO}/git/refs",
            {"ref": f"refs/heads/{BRANCH}", "sha": commit["sha"]},
        )
    print(f"[push] 完成：{commit['sha'][:8]}（{len(changed)} 个文件）")
    return commit["sha"]


def run():
    api(
        "POST",
        f"/repos/{OWNER}/{REPO}/actions/workflows/{WORKFLOW_FILE}/dispatches",
        {"ref": BRANCH},
    )
    print("[run] 已触发 iOS Build（未签名）")


def latest_run():
    runs = api(
        "GET",
        f"/repos/{OWNER}/{REPO}/actions/workflows/{WORKFLOW_FILE}/runs?per_page=1",
    )["workflow_runs"]
    return runs[0] if runs else None


def status(watch=True):
    run_ = latest_run()
    if not run_:
        print("[status] 还没有任何运行记录（先 run）")
        return None
    while True:
        print(
            f"[status] #{run_['run_number']} {run_['status']} / {run_['conclusion']} "
            f"({run_['html_url']})"
        )
        if run_["status"] == "completed" or not watch:
            break
        time.sleep(20)
        run_ = api("GET", f"/repos/{OWNER}/{REPO}/actions/runs/{run_['id']}")
    if run_["conclusion"] != "success":
        jobs = api("GET", f"/repos/{OWNER}/{REPO}/actions/runs/{run_['id']}/jobs")["jobs"]
        for job in jobs:
            print(f"\n=== job {job['name']} ({job['conclusion']}) ===")
            for step in job["steps"]:
                print(f"  {step['number']:>2}. {step['name']}: {step['conclusion']}")
            logs = api(
                "GET",
                f"/repos/{OWNER}/{REPO}/actions/jobs/{job['id']}/logs",
                accept="text/plain",
            )
            text = logs if isinstance(logs, str) else logs.decode("utf-8", "replace")
            print(text[-6000:])
    return run_


def download():
    run_ = latest_run()
    if not run_ or run_["conclusion"] != "success":
        sys.exit("[download] 最近一次运行还没成功，先 status 看看")
    arts = api("GET", f"/repos/{OWNER}/{REPO}/actions/runs/{run_['id']}/artifacts")["artifacts"]
    target = next((a for a in arts if a["name"] == ARTIFACT_NAME), None)
    if not target:
        sys.exit(f"[download] 没找到产物 {ARTIFACT_NAME}，实际有：{[a['name'] for a in arts]}")
    raw = api(
        "GET",
        f"/repos/{OWNER}/{REPO}/actions/artifacts/{target['id']}/zip",
        accept="application/octet-stream",
    )
    os.makedirs(OUT_DIR, exist_ok=True)
    tmp = os.path.join(OUT_DIR, "_artifact.zip")
    with open(tmp, "wb") as f:
        f.write(raw)
    with zipfile.ZipFile(tmp) as z:
        names = z.namelist()
        z.extractall(OUT_DIR)
    os.remove(tmp)
    print(f"[download] 解出：{names}")
    for name in names:
        p = os.path.join(OUT_DIR, name)
        if os.path.exists(p):
            print(f"  {p}  {os.path.getsize(p)/1024/1024:.1f} MB")


def main():
    if not TOKEN:
        sys.exit("需要 GITHUB_TOKEN（repo + workflow 权限）")
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "push":
        push()
    elif cmd == "run":
        run()
    elif cmd == "status":
        status(watch="--no-watch" not in sys.argv)
    elif cmd == "download":
        download()
    elif cmd == "all":
        push()
        run()
        if status() and status(watch=False)["conclusion"] == "success":
            download()
    else:
        sys.exit(f"未知命令：{cmd}（可选 push / run / status / download / all）")


if __name__ == "__main__":
    main()
