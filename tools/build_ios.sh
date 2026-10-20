#!/usr/bin/env bash
# iOS 构建 + 上传脚本（必须在 macOS 上运行）。
# 用法：
#   ./tools/build_ios.sh sim      # ① 模拟器冒烟（拉起 iPhone 模拟器跑 release）
#   ./tools/build_ios.sh ipa      # ② 打正式 ipa（需要签名配置好）
#   ./tools/build_ios.sh unsigned # ③ 未签名包（侧载工具用）
# 详见 docs/iOS.md。
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-ipa}"

case "$MODE" in
  sim)
    echo "==> 在 iPhone 模拟器上运行（Ctrl+C 退出）"
    xcrun simctl list devices available | grep -q "iPhone" \
      || { echo "没有可用的 iPhone 模拟器，先打开 Xcode 装一次模拟器"; exit 1; }
    flutter run --release -d "$(xcrun simctl list devices available | grep -o 'iPhone [^(]*' | head -1)"
    ;;
  ipa)
    echo "==> flutter build ipa --release"
    flutter build ipa --release
    echo "==> 产物："
    ls -lh build/ios/ipa/*.ipa
    echo "==> 上传 TestFlight："
    echo "    Transporter App 拖入上面的 ipa，或"
    echo "    xcrun altool --upload-app -f build/ios/ipa/<名字>.ipa -t ios"
    ;;
  unsigned)
    echo "==> flutter build ios --release --no-codesign"
    flutter build ios --release --no-codesign
    echo "==> 产物：build/ios/iphoneos/Runner.app（用侧载工具安装）"
    ;;
  *)
    echo "未知模式：$MODE（可选 sim / ipa / unsigned）" >&2
    exit 1
    ;;
esac
