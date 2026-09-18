//! Dev-only entry point: run this to wipe all local connections + embedded data.
//!
//! Usage:
//!   cd dbmaster-flutter
//!   flutter run -t lib/dev/cleanup_main.dart -d windows
//!   # or -d macos / -d linux
//!
//! The app asks for confirmation, then cleans up and exits automatically.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'cleanup_embedded_data.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _CleanupApp());
}

class _CleanupApp extends StatefulWidget {
  const _CleanupApp();

  @override
  State<_CleanupApp> createState() => _CleanupAppState();
}

class _CleanupAppState extends State<_CleanupApp> {
  String _status =
      'This tool deletes ALL local connections, credentials, and embedded-server data.\n\n'
      'Make sure you have backups of any production connections before continuing.';
  bool _isCleaning = false;
  bool _done = false;

  Future<void> _startCleanup() async {
    setState(() => _isCleaning = true);
    await _run();
  }

  Future<void> _run() async {
    setState(() => _status = 'Inspecting local storage...');
    await inspectSharedPreferences();

    setState(() => _status = 'Cleaning connections, credentials, embedded data...');
    final summary = await runCleanup();

    final report = await buildReport(summary);
    setState(() {
      _status = report;
      _done = true;
      _isCleaning = false;
    });

    // Auto-exit after showing the report briefly.
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        exit(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _done
                        ? 'Cleanup complete'
                        : (_isCleaning
                            ? 'Cleaning in progress...'
                            : 'Delete all local connection data?'),
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (_isCleaning)
                    const Center(child: CircularProgressIndicator()),
                  SelectableText(
                    _status,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.left,
                  ),
                  const SizedBox(height: 32),
                  if (!_isCleaning && !_done)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: () => exit(0),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _startCleanup,
                          child: const Text('Yes, delete everything'),
                        ),
                      ],
                    ),
                  if (_done)
                    ElevatedButton(
                      onPressed: () => exit(0),
                      child: const Text('Exit'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
