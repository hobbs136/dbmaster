# Contributing to DbMaster

Thanks for your interest in contributing! This repository contains the DbMaster Flutter desktop client — an AI-enhanced database management client licensed under the AGPL-3.0-only.

Bugs, feature requests, and questions go to [GitHub Issues](https://github.com/hobbs136/dbmaster/issues). Security vulnerabilities are handled separately — see [SECURITY.md](SECURITY.md).

## Development setup

1. Install the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel; Dart SDK `^3.11.0` per `pubspec.yaml`). Windows is the primary platform; macOS and Linux also work.
2. Clone and fetch dependencies:

   ```bash
   git clone https://github.com/hobbs136/dbmaster.git
   cd dbmaster
   flutter pub get
   ```

3. Run in development: `flutter run`

After changing `@GenerateMocks` annotations or `.arb` localization files, regenerate the derived code:

```bash
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
```

## Before you submit

Run the verification ladder — a pull request is reviewed only if both pass:

1. `dart analyze lib/` — **no new warnings or errors** (pre-existing info-level lints are the baseline and do not count as new)
2. `flutter test` — the full test suite passes

Keep pull requests focused: one feature or fix per PR, with tests covering it.

## Tests that need databases

Unit and widget tests run fully offline. Integration tests and database-flow tests connect to **real database servers** — database services are never mocked — so you need to provide your own test databases.

- Connection parameters are injected at compile time:

  ```bash
  flutter test integration_test/mysql_integration_test.dart \
    --dart-define=DBMASTER_MYSQL_HOST=<host> \
    --dart-define=DBMASTER_MYSQL_PORT=3306 \
    --dart-define=DBMASTER_MYSQL_USER=<user> \
    --dart-define=DBMASTER_MYSQL_PASSWORD=<password> \
    --dart-define=DBMASTER_MYSQL_DATABASE=<database>
  ```

- The full key list per database type lives in `integration_test/config/*_test_config.dart` (naming scheme: `DBMASTER_<DBTYPE>_<FIELD>`).
- Tests without a configured database **skip automatically**, so the suite stays green on machines without test servers.
- Every database test creates and drops its own temporary database (`dbmaster_test_<timestamp>`) and never touches existing data.

**Never commit credentials, hostnames, or license files** — pass test-database parameters via `--dart-define` at run time only.

## License for contributions

By submitting a pull request or patch to this repository, you agree to license your contribution under the project's license, **AGPL-3.0-only**. This project does not use a CLA or DCO.

## License

DbMaster is licensed under the [GNU Affero General Public License v3.0 only](LICENSE).
