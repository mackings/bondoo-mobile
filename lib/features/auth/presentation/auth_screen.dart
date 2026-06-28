import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/forms/form_validators.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../data/auth_repository.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final formKey = GlobalKey<FormState>();
  bool signup = false;
  bool busy = false;
  final email = TextEditingController();
  final password = TextEditingController();
  final displayName = TextEditingController();
  bool obscurePassword = true;

  Future<void> openForgotPassword() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppTheme.surface,
      builder: (_) => ForgotPasswordSheet(initialEmail: email.text.trim()),
    );
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final auth = ref.read(authControllerProvider.notifier);
      var emailOtpSent = true;
      if (signup) {
        final result = await auth.signUp(
          email: email.text.trim(),
          password: password.text,
          displayName: displayName.text.trim(),
        );
        emailOtpSent = result['email_otp_sent'] != false;
      } else {
        await auth.signIn(email: email.text.trim(), password: password.text);
      }
      if (mounted) {
        await showApiSuccess(
          context,
          title: signup ? 'Account created' : 'Signed in',
          message: signup
              ? emailOtpSent
                    ? 'Your account has been created. Sign in to verify your email and finish setup.'
                    : 'Your account was created, but the email code could not be sent. Sign in and tap Send code again on the verification screen.'
              : 'Welcome back to BONDOO.',
        );
        if (signup && mounted) {
          setState(() {
            signup = false;
            password.clear();
          });
        }
      }
    } catch (error) {
      if (mounted) {
        await showApiError(
          context,
          error,
          title: signup ? 'Could not create account' : 'Could not sign in',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.backgroundSoft, AppTheme.background],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 36, 22, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.primary.withValues(alpha: 0.25),
                            ),
                          ),
                          child: const AssetAvatar(
                            label: 'B',
                            icon: Icons.hub_rounded,
                            size: 68,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'BONDOO',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Welcome to chat banking',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.muted, height: 1.5),
                      ),
                      const SizedBox(height: 36),
                      if (signup) ...[
                        TextFormField(
                          controller: displayName,
                          textInputAction: TextInputAction.next,
                          validator: (value) => FormValidators.requiredText(
                            value,
                            label: 'Display name',
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: FormValidators.email,
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                          prefixIcon: Icon(Icons.alternate_email_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: password,
                        obscureText: obscurePassword,
                        textInputAction: TextInputAction.done,
                        validator: FormValidators.password,
                        onFieldSubmitted: (_) => submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                              () => obscurePassword = !obscurePassword,
                            ),
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (!signup)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: busy ? null : openForgotPassword,
                            child: const Text('Forgot password?'),
                          ),
                        ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: busy ? null : submit,
                        child: busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(signup ? 'Create account' : 'Sign in'),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => signup = !signup),
                        child: Text(
                          signup
                              ? 'Already have an account? Sign in'
                              : 'New here? Create an account',
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
    );
  }
}

class ForgotPasswordSheet extends ConsumerStatefulWidget {
  const ForgotPasswordSheet({super.key, required this.initialEmail});

  final String initialEmail;

  @override
  ConsumerState<ForgotPasswordSheet> createState() =>
      _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends ConsumerState<ForgotPasswordSheet> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController email;
  final code = TextEditingController();
  final password = TextEditingController();
  bool codeSent = false;
  bool busy = false;
  bool obscurePassword = true;

  @override
  void initState() {
    super.initState();
    email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    email.dispose();
    code.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> sendCode() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .requestPasswordReset(email: email.text.trim());
      if (!mounted) return;
      setState(() => codeSent = true);
      await showApiSuccess(
        context,
        title: 'Check your email',
        message: 'If this email is registered, a reset code has been sent.',
      );
    } catch (error) {
      if (mounted) {
        await showApiError(context, error, title: 'Could not send reset code');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetPassword() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .resetPassword(
            email: email.text.trim(),
            code: code.text.trim(),
            password: password.text,
          );
      if (!mounted) return;
      await showApiSuccess(
        context,
        title: 'Password updated',
        message: 'You can now sign in with your new password.',
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        await showApiError(context, error, title: 'Could not reset password');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset + 20),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.lock_reset_rounded,
                color: AppTheme.primaryBright,
                size: 34,
              ),
              const SizedBox(height: 12),
              Text(
                'Reset password',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your email to receive a reset code.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.muted, height: 1.4),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: email,
                enabled: !busy && !codeSent,
                keyboardType: TextInputType.emailAddress,
                textInputAction: codeSent
                    ? TextInputAction.next
                    : TextInputAction.done,
                validator: FormValidators.email,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
                onFieldSubmitted: (_) {
                  if (!codeSent) sendCode();
                },
              ),
              if (codeSent) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: code,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: FormValidators.otp,
                  decoration: const InputDecoration(
                    labelText: 'Reset code',
                    prefixIcon: Icon(Icons.pin_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: password,
                  obscureText: obscurePassword,
                  textInputAction: TextInputAction.done,
                  validator: FormValidators.password,
                  onFieldSubmitted: (_) => resetPassword(),
                  decoration: InputDecoration(
                    labelText: 'New password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => obscurePassword = !obscurePassword),
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: busy
                    ? null
                    : codeSent
                    ? resetPassword
                    : sendCode,
                child: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(codeSent ? 'Reset password' : 'Send reset code'),
              ),
              if (codeSent)
                TextButton(
                  onPressed: busy ? null : sendCode,
                  child: const Text('Resend code'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
