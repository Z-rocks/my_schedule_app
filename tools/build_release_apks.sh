#!/usr/bin/env bash
# 构建 v0.3.4+ 的发布包：一个通用包 + 三个单 ABI 裁剪包。
#
# 为什么不用 `flutter build apk --split-per-abi`：
#   split 会给分架构包塞 versionCode = abiCode*1000 + N（arm64 是 2006），
#   而通用包是 N（6）。两套编号混装必然撞 INSTALL_FAILED_VERSION_DOWNGRADE：
#   装过 2006 就再也装不上 7，用户从 Release 页面随手下个通用包会安装失败。
#
# 这里改成"每个 ABI 单独构建一次"，四个包共用 pubspec 里的同一个
# versionCode，任意包之间都能互相覆盖。
#
# 用法（需要提权，Gradle 要写 ~/.gradle）：
#   bash tools/build_release_apks.sh
# 产物：build/release-apks/{app-release,app-arm64-v8a-release,
#                            app-armeabi-v7a-release,app-x86_64-release}.apk
set -euo pipefail

cd "$(dirname "$0")/.."

# Gradle 9.x 需要 JDK 17+；Android Studio 自带的 jbr 最稳（shell 默认的 17 也行，
# 但历史上踩过假报错，统一用 jbr）。
export JAVA_HOME="${JAVA_HOME_OVERRIDE:-E:/ProgramFiles/Android/jbr}"

OUT="build/release-apks"
SRC="build/app/outputs/flutter-apk/app-release.apk"
rm -rf "$OUT"
mkdir -p "$OUT"

# 单 ABI：--target-platform 决定打进哪些 .so
build_split() {
  local platform="$1" name="$2"
  echo "==> $name ($platform)"
  flutter build apk --release --target-platform "$platform" >/dev/null
  cp "$SRC" "$OUT/$name"
}

# 通用包：不带 --target-platform，三个 ABI 都打进去
build_universal() {
  echo "==> app-release.apk (universal)"
  flutter build apk --release >/dev/null
  cp "$SRC" "$OUT/app-release.apk"
}

build_split android-arm   app-armeabi-v7a-release.apk
build_split android-arm64 app-arm64-v8a-release.apk
build_split android-x64   app-x86_64-release.apk
# 通用包放最后：每次构建都会覆盖 SRC，先复制走裁剪包更安全
build_universal

echo
echo "==> 产物"
ls -lh "$OUT"
