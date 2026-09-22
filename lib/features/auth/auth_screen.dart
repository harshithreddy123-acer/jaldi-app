import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/guest_mode_provider.dart';
import '../../core/role_provider.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isEmailLogin = true;
  String? _error;
  String? _infoMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    setState(() {
      _error = null;
      _infoMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();

    if (!email.contains('@') || password.length < 6) {
      setState(
        () => _error =
            'Please enter a valid email and a password with at least 6 characters.',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final auth = Supabase.instance.client.auth;

      if (_isEmailLogin) {
        final res = await auth.signInWithPassword(
          email: email,
          password: password,
        );
        if (res.session != null && mounted) {
          context.go('/home');
        }
      } else {
        final res = await auth.signUp(
          email: email,
          password: password,
          data: {'full_name': name.isNotEmpty ? name : 'User'},
        );

        if (res.session != null) {
          if (mounted) context.go('/home');
        } else {
          // Email confirmation is required by Supabase project settings
          setState(() {
            _infoMessage =
                'Account created! If email confirmation is enabled, please verify your email. Otherwise, you can now Sign In.';
            _isEmailLogin = true;
          });
        }
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Authentication failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _infoMessage = null;
    });

    try {
      final googleSignIn = GoogleSignIn(
        serverClientId: '868959012606-fnlojq2tmcft5i2i3qcur0hvhk6hrbtk.apps.googleusercontent.com',
        clientId: defaultTargetPlatform == TargetPlatform.iOS
            ? '868959012606-u9ma681gs5cpdjhamck4ovl5a0is15ji.apps.googleusercontent.com'
            : null,
      );
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken != null) {
        final res = await Supabase.instance.client.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: accessToken,
        );
        if (res.session != null && mounted) {
          context.go('/home');
          return;
        }
      } else {
        throw 'No ID token received from Google Play Services.';
      }
    } on AuthException catch (error) {
      debugPrint('[Auth] Supabase AuthException: ${error.message} (${error.statusCode})');
      if (mounted) setState(() => _error = error.message);
    } catch (e, stack) {
      debugPrint('[Auth] Google Sign-In error: $e\n$stack');
      if (mounted) {
        final errStr = e.toString();
        if (errStr.contains('10') || errStr.contains('DEVELOPER_ERROR')) {
          setState(() => _error = 'Google Sign-In developer error (code 10): verify SHA-1 / SHA-256 and OAuth test users.');
        } else {
          setState(() => _error = 'Google Sign-In failed: $errStr');
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _directGuestEntry({bool asProvider = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _infoMessage = null;
    });

    try {
      // 1. Attempt anonymous sign-in in the background if enabled
      try {
        await Supabase.instance.client.auth.signInAnonymously();
      } catch (_) {}

      // 2. Enable Guest / Direct Demo Mode in GoRouter
      ref.read(guestModeProvider.notifier).setGuest(true);
      if (asProvider) {
        ref.read(userRoleProvider.notifier).setRole(UserRole.provider);
      } else {
        ref.read(userRoleProvider.notifier).setRole(UserRole.customer);
      }

      if (mounted) {
        context.go(asProvider ? '/provider' : '/home');
      }
    } catch (e) {
      debugPrint('Direct entry notice: $e');
      ref.read(guestModeProvider.notifier).setGuest(true);
      if (mounted) {
        context.go(asProvider ? '/provider' : '/home');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.car_repair, size: 72, color: Colors.orange),
                const SizedBox(height: 12),
                const Text(
                  'Jaldi',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  _isEmailLogin
                      ? 'Sign in to access 24/7 roadside assistance'
                      : 'Create your account to request or provide help',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 28),

                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_infoMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _infoMessage!,
                            style: const TextStyle(color: Colors.green, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Name field for registration
                if (!_isEmailLogin) ...[
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Email field
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),

                // Password field
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _isEmailLogin ? 'Password' : 'Password (min 6 chars)',
                    prefixIcon: const Icon(Icons.lock),
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_isEmailLogin) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        final email = _emailController.text.trim();
                        context.push(
                          '/forgot-password${email.isNotEmpty ? '?email=${Uri.encodeComponent(email)}' : ''}',
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Primary Button
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _submitEmail,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          _isEmailLogin ? 'Sign In' : 'Create Account',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                const SizedBox(height: 12),

                // Toggle Login / Sign Up
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isEmailLogin = !_isEmailLogin;
                      _error = null;
                      _infoMessage = null;
                    });
                  },
                  child: Text(
                    _isEmailLogin
                        ? "Don't have an account? Create an account"
                        : "Already have an account? Sign In",
                  ),
                ),

                const SizedBox(height: 12),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('OR', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),

                // Google Sign In Button
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  icon: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    child: const Text(
                      'G',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  label: const Text(
                    'Sign in with Google',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Evaluator / Judge Direct Entry Section
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'JUDGES & INSTANT DEMO',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 14),

                // Direct Driver Mode Entry Button
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : () => _directGuestEntry(asProvider: false),
                  icon: const Icon(Icons.flash_on, color: Colors.white),
                  label: const Text(
                    '⚡ Direct Entry (Driver / Customer)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Direct Technician Mode Entry Button
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : () => _directGuestEntry(asProvider: true),
                  icon: const Icon(Icons.build_circle_outlined, color: Colors.deepOrange),
                  label: const Text(
                    '🛠️ Direct Entry (Technician / Provider)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.deepOrange,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: const BorderSide(color: Colors.deepOrange),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Skip sign in and email verification to test all features directly.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
