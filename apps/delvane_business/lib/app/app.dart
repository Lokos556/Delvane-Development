import 'package:flutter/material.dart';
import '../data/mock_business_repository.dart';
import '../domain/business_repository.dart';
import '../shared/app_shell.dart';
import '../core/auth/auth_controller.dart';
import '../core/auth/session_store.dart';
import '../features/workspace/login_page.dart';
import '../features/pms/pms_shell.dart';
import 'controller.dart';
import 'theme.dart';

class DelvaneBusinessApp extends StatefulWidget {
  const DelvaneBusinessApp({
    super.key,
    this.repository,
    this.demoMode = false,
    this.auth,
    this.workspaceBuilder,
  });
  final BusinessRepository? repository;
  final bool demoMode;
  final AuthController? auth;
  final Widget Function(AuthController)? workspaceBuilder;
  @override
  State<DelvaneBusinessApp> createState() => _DelvaneBusinessAppState();
}

class _DelvaneBusinessAppState extends State<DelvaneBusinessApp> {
  BusinessController? controller;
  AuthController? auth;
  late bool showDemo;
  String? navigatorIdentity;
  GlobalKey<NavigatorState> workspaceNavigator = GlobalKey<NavigatorState>();
  @override
  void initState() {
    super.initState();
    showDemo = widget.demoMode;
    if (showDemo) {
      controller = BusinessController(
        widget.repository ?? MockBusinessRepository(),
      )..load();
    } else {
      auth =
          widget.auth ??
          AuthController(
            origin: Uri.parse(
              const String.fromEnvironment(
                'DELVANE_API_ORIGIN',
                defaultValue: 'http://127.0.0.1:8765',
              ),
            ),
            store: const PlatformSessionStore(),
          );
      if (auth!.phase == AuthPhase.restoring) auth!.restore();
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    if (widget.auth == null) auth?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Delvane Business',
    debugShowCheckedModeBanner: false,
    theme: delvaneTheme(),
    home: showDemo
        ? (widget.demoMode
              ? AppShell(controller: controller!)
              : Scaffold(
                  body: SafeArea(
                    child: Column(
                      children: [
                        Material(
                          color: DelvaneColors.yellowSoft,
                          child: ListTile(
                            dense: true,
                            title: const Text('Offline demo · synthetic data'),
                            trailing: TextButton(
                              onPressed: () => setState(() => showDemo = false),
                              child: const Text('Exit demo'),
                            ),
                          ),
                        ),
                        Expanded(child: AppShell(controller: controller!)),
                      ],
                    ),
                  ),
                ))
        : AnimatedBuilder(
            animation: auth!,
            builder: (context, _) {
              if (auth!.phase != AuthPhase.authenticated) {
                return LoginPage(
                  auth: auth!,
                  onDemo: () {
                    controller?.dispose();
                    controller = BusinessController(MockBusinessRepository())
                      ..load();
                    setState(() => showDemo = true);
                  },
                );
              }
              final currentUser = auth!.user!;
              final permissions = currentUser.permissions.toList()..sort();
              final identity =
                  '${currentUser.id}:${currentUser.organizationId}:${currentUser.role}:${permissions.join(',')}';
              if (navigatorIdentity != identity) {
                navigatorIdentity = identity;
                workspaceNavigator = GlobalKey<NavigatorState>();
              }
              // Protected record routes disappear with the authenticated subtree.
              return NavigatorPopHandler<Object?>(
                onPopWithResult: (result) =>
                    workspaceNavigator.currentState?.pop(result),
                child: Navigator(
                  key: workspaceNavigator,
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) =>
                        widget.workspaceBuilder?.call(auth!) ??
                        PmsShell(auth: auth!),
                  ),
                ),
              );
            },
          ),
  );
}
