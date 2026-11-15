#!/bin/bash
# 生成禁用 IPQ8074 ath11k 冷启动校准的补丁
# 用法：在 OpenWrt 源码根目录执行
#   bash gen-ath11k-ipq8074-patch.sh

set -e

# 自动查找 backports 中的 core.c（实际编译使用的）
BACKPORTS_CORE=$(find build_dir -path '*/mac80211-*/backports-*/drivers/net/wireless/ath/ath11k/core.c' 2>/dev/null | head -1)

if [ -z "$BACKPORTS_CORE" ] || [ ! -f "$BACKPORTS_CORE" ]; then
    echo "错误：找不到 backports 中的 ath11k/core.c"
    echo "请先运行：make package/kernel/mac80211/{clean,prepare} V=s"
    exit 1
fi

echo "源文件：$BACKPORTS_CORE"

PATCH_DIR="package/kernel/mac80211/patches/ath11k"
PATCH_NAME="908-wifi-ath11k-disable-coldboot-calibration-for-ipq8074.patch"
TMP_ORIG=$(mktemp)
TMP_MOD=$(mktemp)

cp "$BACKPORTS_CORE" "$TMP_ORIG"
cp "$BACKPORTS_CORE" "$TMP_MOD"

# 定位 IPQ8074 参数段的起止行
L1=$(grep -n '\.hw_rev = ATH11K_HW_IPQ8074,' "$TMP_MOD" | head -1 | cut -d: -f1)
if [ -z "$L1" ]; then
    echo "错误：找不到 IPQ8074 硬件定义（.hw_rev = ATH11K_HW_IPQ8074,）"
    exit 1
fi

L2=$(grep -n '\.hw_rev = ATH11K_HW_' "$TMP_MOD" | awk -F: -v l1="$L1" '$1 > l1 { print $1; exit }')
if [ -z "$L2" ]; then
    L2=$(wc -l < "$TMP_MOD")
fi
# 不把下一段的 hw_rev 行包含进来
L2=$((L2 - 1))

echo "IPQ8074 参数段范围：第 $L1 行 到 第 $L2 行"

# 只在该段内替换
sed -i "${L1},${L2}s/\.coldboot_cal_mm = true,/.coldboot_cal_mm = false,/" "$TMP_MOD"
sed -i "${L1},${L2}s/\.coldboot_cal_ftm = true,/.coldboot_cal_ftm = false,/" "$TMP_MOD"

# 校验：确保每项只改了一处
MODIFIED_MM=$(sed -n "${L1},${L2}p" "$TMP_MOD" | grep -c '\.coldboot_cal_mm = false,')
MODIFIED_FTM=$(sed -n "${L1},${L2}p" "$TMP_MOD" | grep -c '\.coldboot_cal_ftm = false,')

if [ "$MODIFIED_MM" -ne 1 ] || [ "$MODIFIED_FTM" -ne 1 ]; then
    echo "错误：修改结果校验失败（mm=$MODIFIED_MM, ftm=$MODIFIED_FTM）"
    rm -f "$TMP_ORIG" "$TMP_MOD"
    exit 1
fi

# 生成补丁（带 a/ b/ 前缀，符合 OpenWrt patch -p1 格式）
mkdir -p "$PATCH_DIR"
diff -u --label a/drivers/net/wireless/ath/ath11k/core.c \
        --label b/drivers/net/wireless/ath/ath11k/core.c \
        "$TMP_ORIG" "$TMP_MOD" > "$PATCH_DIR/$PATCH_NAME" || true

rm -f "$TMP_ORIG" "$TMP_MOD"

echo ""
echo "=== 生成的补丁 ==="
cat "$PATCH_DIR/$PATCH_NAME"
echo ""
echo "补丁路径：$PATCH_DIR/$PATCH_NAME"
echo ""
echo "下一步："
echo "  make package/kernel/mac80211/{clean,compile} V=s"