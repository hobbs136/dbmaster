#!/bin/bash
# App Store 合规性检查脚本
# 用法: bash scripts/verify_compliance.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

echo "=========================================="
echo "DbMaster App Store 合规性检查"
echo "=========================================="
echo ""

# --- CRIT-001: Release.entitlements 沙盒启用 ---
echo "【CRIT-001】检查 Release.entitlements 沙盒配置..."
RELEASE_ENTITLEMENTS="macos/Runner/Release.entitlements"
if [ ! -f "$RELEASE_ENTITLEMENTS" ]; then
    echo "  ${RED}❌ 文件不存在: $RELEASE_ENTITLEMENTS${NC}"
    ERRORS=$((ERRORS+1))
else
    if ! grep -q "com.apple.security.app-sandbox" "$RELEASE_ENTITLEMENTS"; then
        echo "  ${RED}❌ 缺少 com.apple.security.app-sandbox 键${NC}"
        ERRORS=$((ERRORS+1))
    elif grep -A1 "com.apple.security.app-sandbox" "$RELEASE_ENTITLEMENTS" | grep -q "<false/>"; then
        echo "  ${RED}❌ App Sandbox 被禁用 (false)${NC}"
        ERRORS=$((ERRORS+1))
    else
        echo "  ${GREEN}✅ App Sandbox 已启用${NC}"
    fi

    if ! grep -q "com.apple.security.network.client" "$RELEASE_ENTITLEMENTS"; then
        echo "  ${YELLOW}⚠️  缺少 network.client 权限${NC}"
        WARNINGS=$((WARNINGS+1))
    else
        echo "  ${GREEN}✅ network.client 已配置${NC}"
    fi

    if ! grep -q "com.apple.security.files.user-selected.read-write" "$RELEASE_ENTITLEMENTS"; then
        echo "  ${YELLOW}⚠️  缺少 files.user-selected.read-write 权限${NC}"
        WARNINGS=$((WARNINGS+1))
    else
        echo "  ${GREEN}✅ files.user-selected.read-write 已配置${NC}"
    fi
fi

echo ""

# --- CRIT-002: ITSAppUsesNonExemptEncryption ---
echo "【CRIT-002】检查加密出口合规声明..."
INFO_PLIST="macos/Runner/Info.plist"
if [ ! -f "$INFO_PLIST" ]; then
    echo "  ${RED}❌ 文件不存在: $INFO_PLIST${NC}"
    ERRORS=$((ERRORS+1))
else
    if ! grep -q "ITSAppUsesNonExemptEncryption" "$INFO_PLIST"; then
        echo "  ${RED}❌ 缺少 ITSAppUsesNonExemptEncryption${NC}"
        ERRORS=$((ERRORS+1))
    elif grep -A1 "ITSAppUsesNonExemptEncryption" "$INFO_PLIST" | grep -q "<false/>"; then
        echo "  ${GREEN}✅ ITSAppUsesNonExemptEncryption = false (豁免加密)${NC}"
    elif grep -A1 "ITSAppUsesNonExemptEncryption" "$INFO_PLIST" | grep -q "<true/>"; then
        echo "  ${YELLOW}⚠️  ITSAppUsesNonExemptEncryption = true (需出口许可)${NC}"
        WARNINGS=$((WARNINGS+1))
    else
        echo "  ${YELLOW}⚠️  ITSAppUsesNonExemptEncryption 值不明确${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
fi

echo ""

# --- CRIT-003: NSCameraUsageDescription ---
echo "【CRIT-003】检查相机权限描述..."
if [ ! -f "$INFO_PLIST" ]; then
    echo "  ${RED}❌ 文件不存在: $INFO_PLIST${NC}"
    ERRORS=$((ERRORS+1))
else
    if ! grep -q "NSCameraUsageDescription" "$INFO_PLIST"; then
        echo "  ${RED}❌ 缺少 NSCameraUsageDescription${NC}"
        ERRORS=$((ERRORS+1))
    else
        DESC=$(grep -A1 "NSCameraUsageDescription" "$INFO_PLIST" | grep "<string>" | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
        if [ -z "$DESC" ] || [ "$DESC" = "" ]; then
            echo "  ${RED}❌ NSCameraUsageDescription 值为空${NC}"
            ERRORS=$((ERRORS+1))
        else
            echo "  ${GREEN}✅ NSCameraUsageDescription: $DESC${NC}"
        fi
    fi
fi

echo ""

# --- CRIT-004: PrivacyInfo.xcprivacy ---
echo "【CRIT-004】检查隐私清单..."
PRIVACY_FILE="macos/Runner/PrivacyInfo.xcprivacy"
if [ ! -f "$PRIVACY_FILE" ]; then
    echo "  ${RED}❌ 缺少 PrivacyInfo.xcprivacy${NC}"
    ERRORS=$((ERRORS+1))
else
    echo "  ${GREEN}✅ PrivacyInfo.xcprivacy 文件存在${NC}"

    if grep -q "NSPrivacyTracking" "$PRIVACY_FILE"; then
        echo "  ${GREEN}✅ NSPrivacyTracking 已声明${NC}"
    else
        echo "  ${YELLOW}⚠️  缺少 NSPrivacyTracking${NC}"
        WARNINGS=$((WARNINGS+1))
    fi

    if grep -q "NSPrivacyCollectedDataTypes" "$PRIVACY_FILE"; then
        echo "  ${GREEN}✅ NSPrivacyCollectedDataTypes 已声明${NC}"
    else
        echo "  ${YELLOW}⚠️  缺少 NSPrivacyCollectedDataTypes${NC}"
        WARNINGS=$((WARNINGS+1))
    fi

    if grep -q "NSPrivacyAccessedAPITypes" "$PRIVACY_FILE"; then
        echo "  ${GREEN}✅ NSPrivacyAccessedAPITypes 已声明${NC}"
    else
        echo "  ${YELLOW}⚠️  缺少 NSPrivacyAccessedAPITypes${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
fi

echo ""

# --- HIGH-005: 隐私政策占位符检查 ---
echo "【HIGH-005】检查隐私政策文档..."
PRIVACY_MD="docs/privacy-policy.md"
if [ ! -f "$PRIVACY_MD" ]; then
    echo "  ${RED}❌ 文件不存在: $PRIVACY_MD${NC}"
    ERRORS=$((ERRORS+1))
else
    PLACEHOLDER_COUNT=0
    if grep -q "XX月XX日" "$PRIVACY_MD"; then
        echo "  ${RED}❌ 发现日期占位符: XX月XX日${NC}"
        PLACEHOLDER_COUNT=$((PLACEHOLDER_COUNT+1))
    fi
    if grep -q "你的用户名" "$PRIVACY_MD"; then
        echo "  ${RED}❌ 发现用户名占位符: 你的用户名${NC}"
        PLACEHOLDER_COUNT=$((PLACEHOLDER_COUNT+1))
    fi
    if grep -q "support@dbmaster.app" "$PRIVACY_MD"; then
        echo "  ${YELLOW}⚠️  请确认邮箱地址: support@dbmaster.app${NC}"
        # 不增加错误计数，此邮箱可作为默认支持邮箱
    fi

    if [ "$PLACEHOLDER_COUNT" -eq 0 ]; then
        echo "  ${GREEN}✅ 隐私政策无占位符${NC}"
    else
        ERRORS=$((ERRORS+PLACEHOLDER_COUNT))
    fi
fi

echo ""

# --- MED-001: LSApplicationCategoryType ---
echo "【MED-001】检查应用分类..."
if [ ! -f "$INFO_PLIST" ]; then
    echo "  ${YELLOW}⚠️  无法检查 (Info.plist 不存在)${NC}"
    WARNINGS=$((WARNINGS+1))
else
    if ! grep -q "LSApplicationCategoryType" "$INFO_PLIST"; then
        echo "  ${YELLOW}⚠️  缺少 LSApplicationCategoryType${NC}"
        WARNINGS=$((WARNINGS+1))
    else
        CAT=$(grep -A1 "LSApplicationCategoryType" "$INFO_PLIST" | grep "<string>" | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
        echo "  ${GREEN}✅ LSApplicationCategoryType: $CAT${NC}"
    fi
fi

echo ""
echo "=========================================="
echo "检查结果汇总"
echo "=========================================="
echo ""

if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo "${GREEN}🎉 全部通过！App Store 合规性检查无问题。${NC}"
    exit 0
elif [ "$ERRORS" -eq 0 ]; then
    echo "${GREEN}✅ 无阻塞错误，但有 $WARNINGS 个警告建议修复。${NC}"
    exit 0
else
    echo "${RED}❌ 发现 $ERRORS 个阻塞错误，$WARNINGS 个警告。${NC}"
    echo "${RED}   请先修复错误后再提交 App Store 审核。${NC}"
    exit 1
fi
