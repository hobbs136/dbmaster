# DbMaster

An open-source, AI-enhanced database management client for **MySQL, PostgreSQL, SQLite, MongoDB, Redis, Doris, TDengine, SQL Server, and ClickHouse** — built with Flutter for Windows, macOS, and Linux.

DbMaster is free software licensed under the **GNU AGPL-3.0-only**. Building it from source gives you the complete application with all local features enabled — no purchase or license key required. Official prebuilt binaries and related services are provided by [dbmaster.tech](https://dbmaster.tech) (see [Open source vs. official services](#open-source-vs-official-services)).

## Features

- **9 database types** — MySQL, PostgreSQL, SQLite, MongoDB, Redis, Doris, TDengine, SQL Server, ClickHouse
- **Unlimited connections & query tabs** — no artificial limits
- **SSH tunnel** support
- **AI chat** — bring your own API key (OpenAI / Anthropic / Google / …)
- **Schema Diff** — compare schemas side by side
- **Query Plan Visualization** — visual EXPLAIN with bottleneck analysis + index recommendations
- **DDL Impact Analysis** — schema-change impact assessment with rollback-script generation
- **Query History & Intelligence** — local full-text search + AI-powered recommendations
- **SQL INSERT Export** — export query results as INSERT statements
- **Query Audit Log** — track executed queries with search / filter / CSV export
- **Connection Grouping** — organize connections into folders with drag-and-drop
- **Read-Only Mode** — connect safely without write access
- **Visual ER Diagrams** — generate and explore entity-relationship diagrams
- **Visual Table Editing** — create/edit tables, column filtering, rich data grid
- **Stored Procedures & Triggers** — create, execute, and manage
- **Backup & Restore**
- **Multi-Language** — English, Chinese (Simplified & Traditional), German, French, Russian
- **Dark / Light Theme**

## License

DbMaster is licensed under the **GNU Affero General Public License v3.0 only (AGPL-3.0-only)** — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

If you distribute a modified version of DbMaster, or make its functionality available to users over a network, you must provide the complete corresponding source code to those users under the same license (AGPL-3.0-only).

## Open source vs. official services

The source code in this repository is free software: you can build, use, study, modify, and redistribute it under the AGPL-3.0-only. The following are **paid services from [dbmaster.tech](https://dbmaster.tech)** and are not part of the open-source code:

| Official service (dbmaster.tech, paid) | Do it yourself (free, from source) |
|---|---|
| Prebuilt binaries for each platform | Build your own with the instructions below |
| License issuance & activation | Not required — self-compiled builds have all local features enabled |
| Automatic updates | Pull the latest source and rebuild |
| Technical support | Community help via [GitHub Issues](https://github.com/hobbs136/dbmaster/issues) |

In short: open source does not mean the official services are free, and the official services do not unlock anything extra in the source code.

## Requirements

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel) with Dart SDK `^3.11.0` (see `pubspec.yaml`)
- Windows is the primary platform; macOS and Linux are supported. Web is experimental.

## Building

```bash
git clone https://github.com/hobbs136/dbmaster.git
cd dbmaster
flutter pub get
flutter build windows   # or: flutter build macos | flutter build linux
```

On Windows, the recommended release build is:

```powershell
.\scripts\build_windows.ps1 -Clean
```

The script produces a clean release in `dist\<Mode>\`, bundles the embedded dbmaster-server binary, and subsets the icon fonts. The icon-font subsetting step needs Python 3 + [fonttools](https://fonttools.readthedocs.io/) on the build machine; without it the build still succeeds and simply ships the full icon font.

## Tests

```bash
flutter test
```

The unit/widget suite runs fully offline. Integration tests and database-flow tests connect to **real database servers** (database services are never mocked), which you need to provide yourself. Their connection parameters are injected with `--dart-define`, and tests without a configured database skip automatically:

```bash
flutter test integration_test/mysql_integration_test.dart \
  --dart-define=DBMASTER_MYSQL_HOST=<host> \
  --dart-define=DBMASTER_MYSQL_PORT=3306 \
  --dart-define=DBMASTER_MYSQL_USER=<user> \
  --dart-define=DBMASTER_MYSQL_PASSWORD=<password> \
  --dart-define=DBMASTER_MYSQL_DATABASE=<database>
```

The full key list per database type lives in `integration_test/config/*_test_config.dart` (naming scheme: `DBMASTER_<DBTYPE>_<FIELD>`). Every database test creates and drops its own temporary database (`dbmaster_test_<timestamp>`) and never touches existing data. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## dbmaster-server

DbMaster also pairs with [dbmaster-server](https://github.com/hobbs136/dbmaster-server) — a Rust-based automation engine that adds schema-drift detection and sync, cross-database data sync, health checks, a shared team query library, and other scheduled/team features.

The desktop app automatically runs the server as an embedded local process when its binary is found next to the app executable, or you can connect to a remote server instance from within the app.

## Trademark and branding

The DbMaster name, logo, and other brand assets are **not** licensed under the AGPL: the license covers copyright only and grants no trademark rights. If you distribute a modified version, rename it or clearly label it as an "unofficial fork" so it cannot be mistaken for the official product from dbmaster.tech.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Cmd/Ctrl + N` | New query tab |
| `Cmd/Ctrl + W` | Close current tab |
| `Cmd/Ctrl + Enter` | Execute query |
| `Cmd/Ctrl + Shift + F` | Format SQL |
| `Cmd/Ctrl + Shift + G` | Toggle AI panel full screen |
| `Cmd/Ctrl + Shift + H` | Query history |
| `Cmd/Ctrl + Shift + L` | Query audit log |
| `Cmd/Ctrl + Shift + A` | Toggle AI panel |
| `Cmd/Ctrl + P` / `Cmd/Ctrl + K` | Command palette |

## Contributing and security

- Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for setup, verification steps, and the test-database workflow.
- Found a security vulnerability? Please report it privately — see [SECURITY.md](SECURITY.md).
