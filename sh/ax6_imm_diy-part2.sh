#!/bin/bash
#
# sh/ax6_imm_diy-part2.sh —— 修正版（可直接覆盖仓库同名文件）
#
# 执行时机（见 sh/build.sh）：
#   update.sh（含 feeds install） → 【本脚本】 → apply_config（覆盖 .config） → make defconfig
#
# 因此本脚本能改的只有「包层面」的东西：feeds/*、package/feeds/*、源码树。
# 千万不要在这里 echo CONFIG_* >> .config —— 下一步 apply_config 会用
# deconfig/<设备>.config 整份覆盖，写了也白写，而且不会有任何报错。
# 需要加/减配置项，请改 config/RedMi-AX6_plus_imm.config。
#
# 原版脚本里的四大段内容，三类已由 wrt_core/update.sh 的模块完成，
# 一类完全无效，故统一注释掉（保留原文，方便你以后恢复）：
#   1) PassWall / MosDNS 的 feed 注入    → custom_feed 已提供，注入必被静默跳过
#   2) smartdns / lucky / timecontrol 替换 → update.sh 已做，重复做只会互相覆盖
#   3) n2n 补丁                          → 新配置不含 n2n
#   4) echo CONFIG_* >> .config          → 必被 apply_config 覆盖
#
# 唯一必须保留的新增：把 custom_feed 里的 xray-core 从 26.3.27 抬到 >= 26.7.11，
# 否则 luci-app-passwall(26.10.16) 生成的配置会被旧核心以
#   "this config must be run on version 26.7.11 or higher"
# 拒绝加载，表现为 TCP/UDP/DNS 三个模块全红。
#

set -e

echo "开始 自定义（fichen） 配置……"
echo "========================="

BASE_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)
BUILD_PATH="$BASE_PATH/action_build"

[ -d "$BUILD_PATH" ] || { echo "FATAL: 找不到 $BUILD_PATH（update.sh 是否失败？）"; exit 1; }

# =====================================================================
#  核心修复：xray-core 版本对齐
# =====================================================================
# 来源说明：
#   - luci-app-passwall 来自 custom_feed ← Openwrt-Passwall/openwrt-passwall@main
#   - xray-core        来自 custom_feed ← fichenx/openwrt-package@js（长期停在 26.3.27）
#   - scripts/feeds 对「已安装的源码包」直接 return 0（静默跳过），
#     所以在 diy 里追加 xiaorouji 的 feed 再 install 是无效的，必须直接改这份 Makefile。
#
# 版本/哈希：
#   - 26.7.11 是 PassWall 26.10.16 要求的最低版本，且 go.mod 只要求 Go 1.26，
#     能配合本仓库的 Go 1.26.9 编译出来。
#   - 26.9.9 / 26.10.10 的 go.mod 要求 Go 1.27，在这里会报
#       "go.mod requires go >= 1.27 (running go 1.26.9)" → 编译失败。
#   - 哈希不写死，构建时现算，避免手抄出错（算不出来才退回 skip）。
XRAY_MIN="${XRAY_MIN:-26.7.11}"
XRAY_VER="${XRAY_VER:-26.7.11}"
XRAY_HASH="${XRAY_HASH:-}"

XRAY_MK="$BUILD_PATH/feeds/custom_feed/xray-core/Makefile"

if [ ! -f "$XRAY_MK" ]; then
    echo "FATAL: 找不到 $XRAY_MK"
    exit 1
fi

xray_old=$(sed -n 's/^PKG_VERSION:=//p' "$XRAY_MK" | head -n1)
if [ "$xray_old" != "$XRAY_VER" ]; then
    echo ">>> xray-core: $xray_old -> $XRAY_VER"
    if [ -z "$XRAY_HASH" ]; then
        echo ">>> 现算 ${XRAY_VER} 的 sha256（约 15MB，稍等）..."
        XRAY_HASH=$(curl -fsSL "https://codeload.github.com/XTLS/Xray-core/tar.gz/v${XRAY_VER}" 2>/dev/null \
                    | sha256sum | cut -d' ' -f1)
    fi
    [ -n "$XRAY_HASH" ] || { echo ">>> 哈希计算失败，退回 skip"; XRAY_HASH=skip; }
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$XRAY_VER/" "$XRAY_MK"
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$XRAY_HASH/"       "$XRAY_MK"
fi

# 构建期断言：今后若上游把 PassWall 的最低核心要求再往上抬，
# 这里会直接红叉，而不是让你刷完才发现插件起不来。
ver_ge() {
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

xray_now=$(sed -n 's/^PKG_VERSION:=//p' "$XRAY_MK" | head -n1)
if ! ver_ge "${xray_now:-0}" "$XRAY_MIN"; then
    echo "FATAL: xray-core $xray_now < $XRAY_MIN，PassWall 会拒绝启动。"
    echo "       请把 XRAY_VER / XRAY_HASH 换成更新的官方版本后重试。"
    exit 1
fi

# ---------------------------------------------------------------------
# 打印关键包版本，方便在 Actions 日志里一眼确认（不改任何东西）
# ---------------------------------------------------------------------
print_pkg_version() {
    local mk="$1"
    local name="$2"
    if [ -f "$mk" ]; then
        printf '    %-22s %s\n' "$name" "$(sed -n 's/^PKG_VERSION:=//p' "$mk" | head -n1)"
    fi
}

echo ">>> 关键包版本："
print_pkg_version "$BUILD_PATH/feeds/custom_feed/luci-app-passwall/Makefile" "luci-app-passwall"
print_pkg_version "$XRAY_MK"                                                  "xray-core"
print_pkg_version "$BUILD_PATH/feeds/custom_feed/mosdns/Makefile"             "mosdns"
print_pkg_version "$BUILD_PATH/feeds/custom_feed/chinadns-ng/Makefile"        "chinadns-ng"
print_pkg_version "$BUILD_PATH/feeds/custom_feed/geoview/Makefile"            "geoview"

# =====================================================================
#  以下为原版遗留段落，已停用（保留原文便于恢复）
# =====================================================================

# --- 1) n2n 补丁：新配置不含 n2n，且该包已被 update.sh 处理 ---
# cp -rf $GITHUB_WORKSPACE/res/patch/001-fix-cmake-compatibility.patch $BASE_PATH/action_build/feeds/packages/net/n2n/patches/
# rm -rf $BASE_PATH/action_build/feeds/packages/net/n2n/patches/110-cmake.patch

# --- 2) luci-app-timecontrol：update.sh 的 add_timecontrol() 已克隆 sirpdboy 版本 ---
# rm -rf $BASE_PATH/action_build/feeds/luci/applications/luci-app-timecontrol
# rm -rf $BASE_PATH/action_build/package/luci-app-timecontrol
# git_sparse_clone js https://github.com/gaobin89/luci-app-timecontrol luci-app-timecontrol \
#     && mv -n luci-app-timecontrol $BASE_PATH/action_build/package/luci-app-timecontrol

# --- 3) lucky：custom_feed 已含 lucky / luci-app-lucky，且新配置已删除 lucky ---
# rm -rf $BASE_PATH/action_build/feeds/luci/applications/luci-app-lucky $BASE_PATH/action_build/feeds/packages/net/lucky
# git_sparse_clone main https://github.com/gdy666/luci-app-lucky luci-app-lucky \
#     && mv -n luci-app-lucky $BASE_PATH/action_build/feeds/luci/applications/luci-app-lucky
# git_sparse_clone main https://github.com/gdy666/luci-app-lucky lucky \
#     && mv -n lucky $BASE_PATH/action_build/feeds/packages/net/lucky
# update_lucky

# --- 4) smartdns：update.sh 的 update_smartdns() 已换成 ZqinKing 版本，新配置也不含 smartdns ---
# rm -rf $BASE_PATH/action_build/feeds/packages/net/smartdns
# git_sparse_clone js https://github.com/fichenx/openwrt-package smartdns \
#     && mv -n smartdns $BASE_PATH/action_build/feeds/packages/net/smartdns
# sed -i 's/^PKG_BUILD_PARALLEL:=1/PKG_BUILD_PARALLEL:=0/' $BASE_PATH/action_build/feeds/packages/net/smartdns/Makefile

# --- 5) PassWall / MosDNS feed 注入：custom_feed 已提供，注入会被 scripts/feeds 静默跳过 ---
# echo "src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages.git;main" >> $BASE_PATH/action_build/feeds.conf.default
# echo "src-git passwall https://github.com/xiaorouji/openwrt-passwall.git;main" >> $BASE_PATH/action_build/feeds.conf.default
# echo "src-git mosdns https://github.com/sbwml/luci-app-mosdns.git;v5" >> $BASE_PATH/action_build/feeds.conf.default
# cd $BASE_PATH/action_build
# ./scripts/feeds update -a
# ./scripts/feeds install -a

# --- 6) miniupnpd：update.sh 的 fix_miniupnpd() 已在源树层处理 ---
# rm -rf $BASE_PATH/action_build/feeds/packages/net/miniupnpd

# --- 7) echo CONFIG_* >> .config：会被 build.sh 的 apply_config 整份覆盖 ---
# echo "CONFIG_PACKAGE_luci-app-passwall=y" >> .config
# echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray=y" >> .config
# echo "CONFIG_PACKAGE_luci-app-passwall_Nftables_Transparent_Proxy=y" >> .config
# echo "CONFIG_PACKAGE_luci-app-mosdns=y" >> .config
# echo "CONFIG_PACKAGE_v2ray-geodata=y" >> .config
# echo "CONFIG_PACKAGE_xray-core=y" >> .config
# echo "CONFIG_PACKAGE_shadowsocks-libev-ss-local=y" >> .config
# echo "CONFIG_PACKAGE_shadowsocks-libev-ss-redir=y" >> .config
# echo "CONFIG_PACKAGE_simple-obfs=y" >> .config
# sed -i '/CONFIG_PACKAGE_luci-app-openclash/d' .config
# sed -i '/CONFIG_PACKAGE_luci-app-homeproxy/d' .config
# sed -i '/CONFIG_PACKAGE_luci-app-adguardhome/d' .config
# sed -i '/CONFIG_PACKAGE_luci-app-smartdns/d' .config
# sed -i '/CONFIG_PACKAGE_luci-app-lucky/d' .config
# make defconfig
# sed -i '/CONFIG_PACKAGE_ucode-mod-lua=y/a\ CONFIG_PACKAGE_ucode-mod-math=y' .config

echo "========================="
echo " 自定义(fichen) 配置完成（xray-core $xray_now）"
