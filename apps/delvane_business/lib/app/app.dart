import 'package:flutter/material.dart';
import '../data/mock_business_repository.dart';
import '../domain/business_repository.dart';
import '../shared/app_shell.dart';
import 'controller.dart';
import 'theme.dart';

class DelvaneBusinessApp extends StatefulWidget {
  const DelvaneBusinessApp({super.key, this.repository});
  final BusinessRepository? repository;
  @override
  State<DelvaneBusinessApp> createState() => _DelvaneBusinessAppState();
}

class _DelvaneBusinessAppState extends State<DelvaneBusinessApp> {
  late final BusinessController controller;
  @override
  void initState() {
    super.initState();
    controller = BusinessController(
      widget.repository ?? MockBusinessRepository(),
    )..load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Delvane Business',
    debugShowCheckedModeBanner: false,
    theme: delvaneTheme(),
    home: AppShell(controller: controller),
  );
}
