import 'package:delvane_business/core/localization/web_strings.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_configuration.dart';
import '../../shared/components.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.auth, required this.onDemo});
  final AuthController auth;
  final VoidCallback onDemo;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool hidden = true;
  Future<void> _signIn() async {
    if (widget.auth.busy || !form.currentState!.validate()) return;
    final secret = password.text;
    FocusScope.of(context).unfocus();
    await widget.auth.signIn(email.text, secret);
    if (widget.auth.phase == AuthPhase.authenticated) {
      TextInput.finishAutofillContext(shouldSave: true);
    }
    if (mounted) password.clear();
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Panel(
              child: AutofillGroup(
                onDisposeAction: AutofillContextAction.cancel,
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Image.asset(
                        'assets/delvane-icon.png',
                        width: 72,
                        height: 72,
                        fit: BoxFit.contain,
                        semanticLabel: 'Delvane',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        ui('Delvane AI'),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ui(
                          widget.auth.environment == ApiEnvironment.local
                              ? 'Sign in to your isolated operational workspace. Your backend remains the source of truth.'
                              : 'Sign in to your operational workspace. Your backend remains the source of truth.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.auth.api.baseUrl.origin,
                        style: const TextStyle(color: DelvaneColors.muted),
                      ),
                      const SizedBox(height: 20),
                      if (widget.auth.busy) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(
                          widget.auth.phase == AuthPhase.restoring
                              ? ui(
                                  'Checking development connection and session…',
                                )
                              : ui('Signing in…'),
                        ),
                      ],
                      if (widget.auth.error != null) ...[
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            ui(widget.auth.error!),
                            key: const ValueKey('auth-error'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 12),
                      Text(ui('Fields marked with * are required.')),
                      const SizedBox(height: 12),
                      TextFormField(
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        key: const ValueKey('login-email'),
                        controller: email,
                        enabled: !widget.auth.busy,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email,
                        ],
                        decoration: InputDecoration(
                          labelText: '${ui('Email')} *',
                        ),
                        validator: (v) => v == null || !v.contains('@')
                            ? ui('Enter your account email.')
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        key: const ValueKey('login-password'),
                        controller: password,
                        enabled: !widget.auth.busy,
                        obscureText: hidden,
                        autofillHints: const [AutofillHints.password],
                        enableSuggestions: false,
                        autocorrect: false,
                        onFieldSubmitted: (_) => _signIn(),
                        decoration: InputDecoration(
                          labelText: '${ui('Password')} *',
                          suffixIcon: IconButton(
                            tooltip: ui(
                              hidden ? 'Show password' : 'Hide password',
                            ),
                            onPressed: () => setState(() => hidden = !hidden),
                            icon: Icon(
                              hidden
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? ui('Enter your password.')
                            : null,
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        key: const ValueKey('sign-in'),
                        onPressed: widget.auth.busy ? null : _signIn,
                        child: Text(ui('Sign in')),
                      ),
                      TextButton(
                        onPressed: widget.auth.busy
                            ? null
                            : widget.auth.restore,
                        child: Text(ui('Reconnect / restore session')),
                      ),
                      const Divider(height: 28),
                      OutlinedButton(
                        onPressed: widget.auth.busy ? null : widget.onDemo,
                        child: Text(ui('Explore offline demo')),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        ui(
                          'Demo mode is separate and never substitutes for a failed API request. Passwords are never saved.',
                        ),
                        style: TextStyle(
                          color: DelvaneColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
