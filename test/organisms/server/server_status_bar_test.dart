// Widget tests for ServerStatusBar
// =============================================================================
// Tests all four connection state rendering variants using test state injection.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/health_check_provider.dart';
import 'package:dbmaster/providers/approval_provider.dart';
import 'package:dbmaster/services/server_connection.dart';
import 'package:dbmaster/organisms/server/server_status_bar.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Pump [ServerStatusBar] with a [ServerConnectionProvider].
Future<ServerConnectionProvider> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});

  final provider = ServerConnectionProvider();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(Colors.blue),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<ServerConnectionProvider>.value(
              value: provider,
            ),
            // HealthCheckProvider is watched by the health alert badge added
            // in _buildConnected; register it (guard=false so no refresh fires).
            ChangeNotifierProvider<HealthCheckProvider>(
              create: (_) => HealthCheckProvider(shouldRefresh: () => false),
            ),
            // ApprovalProvider is watched by the pending-approval badge added
            // in _buildConnected; register it (guard=false so no refresh fires).
            ChangeNotifierProvider<ApprovalProvider>(
              create: (_) => ApprovalProvider(shouldRefresh: () => false),
            ),
          ],
          child: const ServerStatusBar(),
        ),
      ),
    ),
  );
  return provider;
}

void main() {
  tearDown(() {
    ServerConnection.resetForTesting();
  });

  group('ServerStatusBar', () {
    // ── Disconnected ──

    testWidgets('shows Not connected when disconnected', (tester) async {
      await _pump(tester);
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.byIcon(LucideIcons.cloudOff), findsOneWidget);
    });

    testWidgets('click in disconnected state opens connect dialog', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.text('Not connected'));
      await tester.pumpAndSettle();

      // Connect dialog should appear
      expect(find.text('Connect to Server'), findsOneWidget);
    });

    // ── Connecting ──

    testWidgets('shows Connecting… spinner', (tester) async {
      final provider = await _pump(tester);
      provider.setTestState(connectionState: ServerConnectionState.connecting);
      await tester.pump();

      expect(find.text('Connecting…'), findsOneWidget);
    });

    // ── Connected ──

    testWidgets('shows green dot with hostname', (tester) async {
      final provider = await _pump(tester);
      provider.setTestState(
        connectionState: ServerConnectionState.connected,
        serverUrl: 'https://myserver.example.com:3000',
        userProfile: const ServerUserProfile(
          id: 'u1',
          email: 'test@example.com',
          displayName: 'Test User',
        ),
      );
      await tester.pump();

      // Should show the hostname
      expect(find.text('myserver.example.com'), findsOneWidget);
    });

    // ── Reconnecting ──

    testWidgets('shows Reconnecting… spinner', (tester) async {
      final provider = await _pump(tester);
      provider.setTestState(
        connectionState: ServerConnectionState.reconnecting,
      );
      await tester.pump();

      expect(find.text('Reconnecting…'), findsOneWidget);
    });

    // ── Embedded gating ──

    testWidgets(
      'embedded mode marks drift/health/MCP menu entries remote-only',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1400, 900));
        final provider = await _pump(tester);
        provider.setTestState(
          connectionState: ServerConnectionState.connected,
          serverUrl: 'http://127.0.0.1:12345',
          userProfile: const ServerUserProfile(
            id: 'u1',
            email: 'embedded@local',
            displayName: 'Local User',
          ),
          embedded: true,
        );
        await tester.pump();

        // Embedded pill shows "Local" instead of a hostname.
        expect(find.text('127.0.0.1'), findsNothing);
        await tester.tap(find.text('Local'));
        await tester.pumpAndSettle();

        // Drift / health check / MCP tokens each carry the remote-only hint;
        // data sync / team query / approval / workspace stay unmarked.
        expect(find.text('Remote server only'), findsNWidgets(3));
        expect(find.text('Disconnect'), findsOneWidget);
        // reports-M1（#29）— 慢查询统计在 embedded 不禁用（主场景），且无
        // remote-only 提示（上面 NWidgets(3) 已隐含：它不是第 4 个）。
        expect(find.text('Slow Query Stats'), findsOneWidget);

        await tester.binding.setSurfaceSize(null);
      },
    );

    testWidgets('remote connected menu has no remote-only hints', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      final provider = await _pump(tester);
      provider.setTestState(
        connectionState: ServerConnectionState.connected,
        serverUrl: 'https://myserver.example.com:3000',
        userProfile: const ServerUserProfile(
          id: 'u1',
          email: 'test@example.com',
          displayName: 'Test User',
        ),
      );
      await tester.pump();

      await tester.tap(find.text('myserver.example.com'));
      await tester.pumpAndSettle();

      expect(find.text('Remote server only'), findsNothing);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('connected menu offers the server-connections entry (U05)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      final provider = await _pump(tester);
      provider.setTestState(
        connectionState: ServerConnectionState.connected,
        serverUrl: 'https://myserver.example.com:3000',
        userProfile: const ServerUserProfile(
          id: 'u1',
          email: 'test@example.com',
          displayName: 'Test User',
        ),
      );
      await tester.pump();

      await tester.tap(find.text('myserver.example.com'));
      await tester.pumpAndSettle();

      // The registry-management entry is available in remote mode (its main
      // purpose — remote deployments had no writer for server connections).
      expect(find.text('Server connections'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    // ── Widget structure ──

    testWidgets('does not crash on any state', (tester) async {
      final provider = await _pump(tester);

      for (final state in ServerConnectionState.values) {
        provider.setTestState(connectionState: state);
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Crash on state: $state',
        );
      }
    });
  });
}
