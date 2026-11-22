import 'package:delvane_business/core/localization/web_strings.dart';
import 'package:material_ui/material_ui.dart';

import 'dart:async';

import '../data/mock_business_repository.dart';
import '../domain/business_repository.dart';
import '../shared/app_shell.dart';
import '../core/auth/auth_controller.dart';
import '../core/auth/session_store.dart';
import '../core/network/api_configuration.dart';
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
  bool _localeReady = false;
  String? configurationError;
  String? navigatorIdentity;
  GlobalKey<NavigatorState> workspaceNavigator = GlobalKey<NavigatorState>();
  @override
  void initState() {
    super.initState();
    WebStrings.current.addListener(_languageChanged);
    unawaited(
      WebStrings.current
          .initialize(widget.auth?.store ?? const PlatformSessionStore())
          .then((_) {
            if (mounted) setState(() => _localeReady = true);
          }),
    );
    showDemo = widget.demoMode;
    if (showDemo) {
      controller = BusinessController(
        widget.repository ?? MockBusinessRepository(),
      )..load();
    } else {
      try {
        final configuration = widget.auth == null
            ? ApiConfiguration.fromBuild()
            : null;
        auth =
            widget.auth ??
            AuthController(
              origin: configuration!.origin,
              environment: configuration.environment,
              uatTunnelCertificate: configuration.uatTunnelCertificate,
              store: const PlatformSessionStore(),
            );
        if (auth!.phase == AuthPhase.restoring) auth!.restore();
      } on ArgumentError {
        // Do not log invalid URLs: they might contain accidentally embedded secrets.
        configurationError = 'Invalid API configuration. Check the build environment and backend origin.';
      }
    }
  }

  @override
  void dispose() {
    WebStrings.current.removeListener(_languageChanged);
    controller?.dispose();
    if (widget.auth == null) auth?.dispose();
    super.dispose();
  }

  void _languageChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: Locale(WebStrings.current.language),
    supportedLocales: const [Locale('hu'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    title: 'Delvane AI',
    debugShowCheckedModeBanner: false,
    theme: delvaneTheme(),
    home: !_localeReady
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : configurationError != null
        ? Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(ui(configurationError!)),
                ),
              ),
            ),
          )
        : showDemo
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
                            title: Text(ui('Offline demo · synthetic data')),
                            trailing: TextButton(
                              onPressed: () => setState(() => showDemo = false),
                              child: Text(ui('Exit demo')),
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
