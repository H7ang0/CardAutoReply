#!/bin/bash
# CardAutoReply 构建脚本
# 用法：
#   ./build.sh                 # 只编译
#   ./build.sh package         # 打 rootful .deb -> ./packages/
#   ./build.sh package rootless# 打 rootless .deb
#   ./build.sh clean
#
# 为什么要这个脚本：
#  - Theos 需要环境变量 THEOS（这里默认 ~/theos）
#  - Xcode 16/26 上 `xcodebuild -sdk '' -find make` 会 abort，导致 Theos 找不到 make；
#    把 DEVELOPER_DIR 指向独立的 Command Line Tools 即可绕过（Theos 的 iOS SDK 在
#    $THEOS/sdks，不依赖 Xcode）。必须在“环境里”设置，写进 Makefile 无效。

set -e
export THEOS="${THEOS:-$HOME/theos}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"

cd "$(dirname "$0")"

if [ "$2" = "rootless" ] || [ "$1" = "rootless" ]; then
  export THEOS_PACKAGE_SCHEME=rootless
  # 去掉参数里的 rootless
  set -- "${@/rootless/}"
fi

exec make "$@"
