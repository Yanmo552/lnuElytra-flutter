import 'dart:io';

import 'package:flutter/material.dart';

import 'components/toast.dart';
import 'services/auto_start.dart';
import 'services/log_store.dart';
import 'src/rust/frb_generated.dart';
import 'views/responsive_shell.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  logStore.start();

  autoStart = AutoStartRequest.parse(args);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'lnuElytra',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0076C1),
        fontFamily: Platform.isWindows ? '微软雅黑' : null,
      ),
      builder: (context, child) =>
          ToastOverlay(child: child ?? const SizedBox.shrink()),
      home: const ResponsiveShell(),
    );
  }
}
