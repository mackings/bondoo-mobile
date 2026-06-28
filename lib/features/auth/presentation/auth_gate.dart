import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/notifications/push_notifications.dart';
import '../../admin/presentation/admin_dashboard_screen.dart';
import '../../calls/presentation/call_invite_listener.dart';
import '../../home/presentation/home_shell.dart';
import '../data/auth_repository.dart';
import 'account_setup_screen.dart';
import 'auth_screen.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  String? registeredForUserId;

  void maybeRegisterPushToken(AuthState auth) {
    final userId = auth.user?['id'] as String?;
    if (!auth.isAuthenticated ||
        userId == null ||
        registeredForUserId == userId) {
      return;
    }
    registeredForUserId = userId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      PushNotifications.register(ref.read(apiClientProvider));
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    maybeRegisterPushToken(auth);
    if (auth.restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!auth.isAuthenticated) return const AuthScreen();
    final user = auth.user!;
    if (user['role'] == 'admin') {
      return const CallInviteListener(child: AdminDashboardScreen());
    }
    if (user['email_verified'] != true) {
      return const EmailVerificationScreen();
    }
    return const CallInviteListener(child: HomeShell());
  }
}
