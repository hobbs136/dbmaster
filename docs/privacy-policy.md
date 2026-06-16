# DbMaster  Privacy Policy

**Last Updated**: 2026-06-16

---

## English Version

### 1. Overview

DbMaster (hereinafter referred to as "this App") is a database management client software. We take your privacy seriously. This privacy policy explains how this App handles your information.

### 2. Data Collection

**This App does not collect any user data.**

Specifically, we do not collect:
- Personal identification information
- Usage behavior data
- Device information
- Location information
- Any other user data

All database connections, AI requests, and purchase validations are initiated directly from your device and do not pass through our servers.

### 3. Data Storage

All data is stored locally on your device:

- **Database connection information**: Stored in your device's local storage
- **Database passwords**: Securely stored using macOS Keychain (via `flutter_secure_storage`)
- **AI API Keys**: Securely stored using macOS Keychain (via `flutter_secure_storage`)
- **Query history**: Stored in your device's local SQLite database in plain text
- **AI conversation records**: Stored as plain text JSON files in your app's Documents directory
- **Audit logs**: Stored in your device's local storage in plain text, with sensitive values (such as passwords) in SQL statements automatically masked
- **App settings**: Stored in your device's local storage
- **Pro subscription status**: Securely stored using macOS Keychain (via `flutter_secure_storage`)

### 4. Third-Party Services

#### 4.1 AI Features

The AI features of this App require you to provide your own API Key (such as DeepSeek, Kimi, etc.). All AI requests are sent directly from your device to the AI service provider of your choice. This App does not relay requests through our servers.

The AI service provider you choose has its own privacy policy. Please refer to:
- DeepSeek: https://www.deepseek.com/privacy
- Kimi (Moonshot AI): https://kimi.moonshot.cn/privacy

#### 4.2 Database Connections

This App allows you to connect to your own database servers. All database connections are established directly from your device and do not go through our servers.

#### 4.3 In-App Purchases and Subscriptions

This App offers auto-renewable subscriptions (DbMaster Pro) through Apple App Store. All purchase processing, payment information, and subscription status are managed by Apple. Apple may collect information related to purchases. Please refer to Apple's privacy policy:
https://www.apple.com/legal/privacy/

### 5. Data Security

We take the following measures to protect your data:
- Sensitive information (such as database passwords, AI API keys, and Pro status) is encrypted and stored using macOS Keychain
- All network connections use SSL/TLS encryption
- Local data is stored in the app sandbox, isolated from other apps
- Sensitive SQL values in audit logs are automatically masked before being recorded

### 6. Children's Privacy

This App is not intended for children under 13 years of age. We do not knowingly collect personal information from children.

### 7. Changes to Privacy Policy

We may update this privacy policy from time to time. Updated policies will be posted on this page.

### 8. Contact Us

If you have any questions about this privacy policy, please contact us at:

- GitHub Issues: https://github.com/YOUR_GITHUB_USERNAME/dbmaster/issues
- Email: support@dbmaster.app

> **TODO**: Please replace `YOUR_GITHUB_USERNAME` with your real GitHub username and `support@dbmaster.app` with your real support email.

---

## 中文版

### 1. 概述

DbMaster（以下简称"本应用"）是一款数据库管理客户端软件。我们高度重视您的隐私保护。本隐私政策旨在向您说明本应用如何处理您的信息。

### 2. 数据收集

**本应用不收集任何用户数据。**

具体而言，我们不会收集：
- 个人身份信息
- 使用行为数据
- 设备信息
- 位置信息
- 任何其他用户数据

所有数据库连接、AI 请求、购买验证均直接从您的设备发起，不会经过我们的服务器中转。

### 3. 数据存储

所有数据均存储在您的本地设备上：

- **数据库连接信息**：存储在您设备的本地存储中
- **数据库密码**：使用 macOS Keychain（通过 `flutter_secure_storage`）安全存储
- **AI API Key**：使用 macOS Keychain（通过 `flutter_secure_storage`）安全存储
- **查询历史**：以明文形式存储在您设备的本地 SQLite 数据库中
- **AI 会话记录**：以明文 JSON 文件形式存储在您设备的应用文档目录中
- **审计日志**：以明文形式存储在您设备的本地存储中，其中 SQL 语句中的密码等敏感值会自动脱敏处理
- **应用设置**：存储在您设备的本地存储中
- **Pro 订阅状态**：使用 macOS Keychain（通过 `flutter_secure_storage`）安全存储

### 4. 第三方服务

#### 4.1 AI 功能

本应用的 AI 功能需要您提供自己的 API Key（如 DeepSeek、Kimi 等）。所有 AI 请求直接从您的设备发送到您选择的 AI 服务商，本应用不会经过我们的服务器中转。

您选择的 AI 服务商有其独立的隐私政策，请参阅：
- DeepSeek: https://www.deepseek.com/privacy
- Kimi (月之暗面): https://kimi.moonshot.cn/privacy

#### 4.2 数据库连接

本应用允许您连接到您自己的数据库服务器。所有数据库连接直接从您的设备建立，不会经过我们的服务器。

#### 4.3 内购与订阅

本应用通过 Apple App Store 提供自动续订订阅（DbMaster Pro）。所有购买处理、支付信息、订阅状态均由 Apple 管理。Apple 可能会收集与购买相关的信息，请参阅 Apple 的隐私政策：
https://www.apple.com/legal/privacy/

### 5. 数据安全

我们采取以下措施保护您的数据：
- 敏感信息（如数据库密码、AI API Key、Pro 状态）使用 macOS Keychain 加密存储
- 所有网络连接使用 SSL/TLS 加密
- 本地数据存储在应用沙盒中，与其他应用隔离
- 审计日志中的敏感 SQL 值在记录前自动脱敏

### 6. 儿童隐私

本应用不面向 13 岁以下儿童。我们不会故意收集儿童的个人信息。

### 7. 隐私政策变更

我们可能会不时更新本隐私政策。更新后的政策将在本页面发布。

### 8. 联系我们

如果您对本隐私政策有任何疑问，请通过以下方式联系我们：

- GitHub Issues: https://github.com/YOUR_GITHUB_USERNAME/dbmaster/issues
- Email: support@dbmaster.app

> **TODO**: 请将 `YOUR_GITHUB_USERNAME` 替换为您的真实 GitHub 用户名，将 `support@dbmaster.app` 替换为您的真实支持邮箱。

