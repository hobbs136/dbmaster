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

- GitHub Issues: https://github.com/hobbs136/dbmaster/issues
- Email: hobbs136@hotmail.com

