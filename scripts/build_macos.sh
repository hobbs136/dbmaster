#!/bin/bash

# DbMaster macOS构建脚本

# 颜色定义
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

echo -e "${GREEN}=== DbMaster macOS 构建脚本 ===${NC}"

# 解析构建模式参数（默认 release）
BUILD_MODE="release"
if [ "$1" = "--debug" ]; then
    BUILD_MODE="debug"
elif [ "$1" = "--release" ] || [ "$1" = "" ]; then
    BUILD_MODE="release"
else
    echo -e "${YELLOW}用法: $0 [--debug | --release] (默认: release)${NC}"
    exit 1
fi

# 检查 Release 模式签名配置：keychain-access-groups 需要 DEVELOPMENT_TEAM / 签名证书
check_release_signing() {
    local settings team identity profile
    settings=$(xcodebuild -project macos/Runner.xcodeproj -target Runner -configuration Release -showBuildSettings 2>/dev/null)
    team=$(echo "$settings" | sed -n 's/^ *DEVELOPMENT_TEAM = \(.*\)/\1/p' | xargs)
    identity=$(echo "$settings" | sed -n 's/^ *CODE_SIGN_IDENTITY = \(.*\)/\1/p' | xargs)
    profile=$(echo "$settings" | sed -n 's/^ *PROVISIONING_PROFILE_SPECIFIER = \(.*\)/\1/p' | xargs)

    if [ -z "$team" ] && [ -z "$profile" ]; then
        return 1
    fi
    if [ -z "$identity" ] || [ "$identity" = "-" ]; then
        return 1
    fi
    return 0
}

if [ "$BUILD_MODE" = "release" ]; then
    if ! check_release_signing; then
        echo -e "${YELLOW}警告: 当前未配置 macOS Release 签名（缺少 DEVELOPMENT_TEAM / CODE_SIGN_IDENTITY）。${NC}"
        echo -e "${YELLOW}      由于 Release.entitlements 包含 keychain-access-groups，无签名无法构建。${NC}"
        echo -e "${YELLOW}      自动降级为 Debug 构建以继续；如需 Release，请在 Xcode → Signing & Capabilities 中选择 Team。${NC}"
        BUILD_MODE="debug"
    fi
fi

echo -e "${GREEN}构建模式: ${BUILD_MODE}${NC}"

# 检查Flutter是否安装
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}错误: Flutter 未安装或未添加到PATH中${NC}"
    echo -e "${YELLOW}请访问 https://flutter.dev/docs/get-started/install/macos 安装Flutter${NC}"
    exit 1
fi

echo -e "${GREEN}Flutter 已安装，检查版本...${NC}"
flutter --version

# 检查Xcode是否安装
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}错误: Xcode 未安装或未添加到PATH中${NC}"
    echo -e "${YELLOW}请从App Store安装Xcode，或运行: xcode-select --install${NC}"
    echo -e "${YELLOW}安装后请运行: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer${NC}"
    echo -e "${YELLOW}然后运行: sudo xcodebuild -runFirstLaunch${NC}"
    exit 1
fi

# 检查CocoaPods是否安装
if ! command -v pod &> /dev/null; then
    echo -e "${RED}错误: CocoaPods 未安装${NC}"
    echo -e "${YELLOW}请运行: sudo gem install cocoapods${NC}"
    exit 1
fi

# 进入项目根目录
cd "$(dirname "$(dirname "$0")")" || {
    echo -e "${RED}错误: 无法进入项目根目录${NC}"
    exit 1
}

echo -e "${GREEN}项目根目录: $(pwd)${NC}"

# 检查依赖
echo -e "${GREEN}检查并更新依赖...${NC}"
flutter pub get
if [ $? -ne 0 ]; then
    echo -e "${RED}错误: 依赖安装失败${NC}"
    exit 1
fi

# 运行flutter doctor确保环境正确
echo -e "${GREEN}运行 flutter doctor 检查环境...${NC}"
flutter doctor

# 构建macOS版本
echo -e "${GREEN}开始构建macOS版本...${NC}"

# U15：注入 APP_VERSION（git tag，遥测/更新检查共用；取不到 = dev 构建）
APP_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "dev")
echo -e "${GREEN}APP_VERSION: ${APP_VERSION}${NC}"

# Xcode已安装，尝试正常构建
flutter build macos --${BUILD_MODE} --dart-define=APP_VERSION="${APP_VERSION}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}构建成功!${NC}"
    echo -e "${GREEN}构建产物路径: $(pwd)/build/macos/Build/Products/${BUILD_MODE}/DbMaster.app${NC}"
    
    # T28：SQL Server 经网关，FreeTDS 打包步骤已随 FFI 下线移除。
    # embedded 模式需 dbmaster-server 与 app 同目录（DBMASTER_SERVER_BIN 可覆盖）。
    
    # 提示如何运行应用
    echo -e "${YELLOW}运行应用命令: open build/macos/Build/Products/${BUILD_MODE}/DbMaster.app${NC}"
    
    # 提示如何验证构建结果
    echo -e "${YELLOW}验证应用: 右键点击DbMaster.app -> 显示包内容，检查Contents/MacOS/DbMaster是否存在${NC}"
else
    echo -e "${RED}构建失败!${NC}"
    echo -e "${YELLOW}请检查以上错误信息，确保所有依赖都已正确安装${NC}"
    exit 1
fi

echo -e "${GREEN}=== 构建完成 ===${NC}"
