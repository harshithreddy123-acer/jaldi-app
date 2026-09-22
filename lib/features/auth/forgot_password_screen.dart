import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/router.dart';

enum ResetStep { requestEmail, linkSent }

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  final String? initialEmail;
  final bool isDirectReset;

  const ForgotPasswordScreen({
    super.key,
    this.initialEmail,
    this.isDirectReset = false,
  });

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  late ResetStep _step;
  bool _isLoading = false;
  bool _showManualOtp = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  String? _error;
  String? _infoMessage;

  Timer? _resendTimer;
  int _resendCountdown = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
      _emailController.text = widget.initialEmail!;
    }
    _step = widget.isDirectReset ? ResetStep.linkSent : ResetStep.requestEmail;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendCountdown <= 1) {
        timer.cancel();
        setState(() => _resendCountdown = 0);
      } else {
        setState(() => _resendCountdown--);
      }
    });
  }

  Future<void> _sendResetLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _infoMessage = null;
    });

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'jaldi://reset-password',
      );
      if (mounted) {
        setState(() {
          _step = ResetStep.linkSent;
          _infoMessage = 'Reset link sent! Check your inbox.';
        });
        _startResendTimer();
      }
    } on AuthException catch (e) {
      debugPrint('[Auth] resetPasswordForEmail error: ${e.message} (${e.statusCode})');
      if (mounted) {
        String msg = e.message;
        if (msg.toLowerCase().contains('rate limit') || e.statusCode == '429') {
          msg = 'Email rate limit reached: Supabase free tier limits built-in emails to a few per hour. To remove this limit, set up free Gmail SMTP in your Supabase dashboard.';
        }
        setState(() => _error = msg);
      }
    } catch (e, stack) {
      debugPrint('[Auth] resetPasswordForEmail unexpected: $e\n$stack');
      if (mounted) setState(() => _error = 'Failed to send reset link: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitPasswordUpdate({bool isUsingOtp = false}) async {
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    if (isUsingOtp && otp.length < 6) {
      setState(() => _error = 'Please enter the 6-digit verification code.');
      return;
    }

    if (newPassword.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    if (newPassword != confirmPassword) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _infoMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;

      if (isUsingOtp) {
        final cleanInput = otp.trim();
        String extractedToken = cleanInput;

        // If the user pasted a full URL (from email button or browser)
        if (cleanInput.startsWith('http://') ||
            cleanInput.startsWith('https://') ||
            cleanInput.startsWith('jaldi://')) {
          final uri = Uri.tryParse(cleanInput);
          if (uri != null) {
            final tokenParam = uri.queryParameters['token'] ??
                uri.queryParameters['code'] ??
                uri.queryParameters['token_hash'] ??
                Uri.splitQueryString(uri.fragment)['access_token'];
            if (tokenParam != null && tokenParam.isNotEmpty) {
              extractedToken = tokenParam;
            }
          }
        }

        final normalizedCode = extractedToken.replaceAll(RegExp(r'\s+|-'), '');
        final cleanEmail = email.toLowerCase().trim();

        debugPrint('[Auth] Verifying recovery token: length=${normalizedCode.length}, isNumeric=${RegExp(r'^\d{6,8}$').hasMatch(normalizedCode)}, email=$cleanEmail');

        // If it's a numeric 6-8 digit OTP code
        if (RegExp(r'^\d{6,8}$').hasMatch(normalizedCode)) {
          await supabase.auth.verifyOTP(
            email: cleanEmail,
            token: normalizedCode,
            type: OtpType.recovery,
          );
        } else {
          // It's a token hash (from email link or URL)
          await supabase.auth.verifyOTP(
            tokenHash: extractedToken,
            type: OtpType.recovery,
          );
        }
      }

      await supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      // Clear recovery state in router notifier
      ref.read(authRouterNotifierProvider).clearRecovery();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('Password updated successfully! Welcome back.'),
          ),
        );
        if (supabase.auth.currentSession != null) {
          context.go('/home');
        } else {
          context.go('/auth');
        }
      }
    } on AuthException catch (e) {
      debugPrint('[Auth] verifyOTP/updateUser AuthException: ${e.message} (${e.statusCode})');
      if (mounted) {
        String msg = e.message;
        if (msg.toLowerCase().contains('expired') || msg.toLowerCase().contains('invalid')) {
          msg = 'The code or link is invalid or expired. Note: If you requested reset multiple times, only the newest code/link works.';
        }
        setState(() => _error = msg);
      }
    } catch (e, stack) {
      debugPrint('[Auth] unexpected error during password reset: $e\n$stack');
      if (mounted) setState(() => _error = 'Failed to update password: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // If opened directly from deep link / recovery session
    final isDirectLinkRecovery = widget.isDirectReset;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isDirectLinkRecovery
              ? 'Set New Password'
              : _step == ResetStep.requestEmail
                  ? 'Forgot Password'
                  : 'Check Your Email',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_step == ResetStep.linkSent && !isDirectLinkRecovery) {
              setState(() {
                _step = ResetStep.requestEmail;
                _showManualOtp = false;
                _error = null;
                _infoMessage = null;
              });
            } else {
              ref.read(authRouterNotifierProvider).clearRecovery();
              context.go('/auth');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Icon
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isDirectLinkRecovery
                          ? Icons.lock_open_rounded
                          : _step == ResetStep.requestEmail
                              ? Icons.lock_reset_rounded
                              : Icons.mark_email_read_rounded,
                      size: 56,
                      color: Colors.orange,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title and Description
                if (isDirectLinkRecovery) ...[
                  const Text(
                    'Create New Password',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your email has been verified via the reset link. Enter your new password below.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ] else if (_step == ResetStep.requestEmail) ...[
                  const Text(
                    'Forgot Your Password?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Enter your registered email and we'll send you a password reset link.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ] else ...[
                  const Text(
                    'Check Your Email',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We sent a password reset link to ${_emailController.text.trim()}.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
                const SizedBox(height: 24),

                // Error Banner
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

                // Info Banner
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

                // View 1: Direct Link Recovery (User clicked email link)
                if (isDirectLinkRecovery) ...[
                  TextField(
                    controller: _newPasswordController,
                    obscureText: _obscureNewPassword,
                    decoration: InputDecoration(
                      labelText: 'New Password (min 6 chars)',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureNewPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscureNewPassword = !_obscureNewPassword,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Confirm New Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscureConfirmPassword = !_obscureConfirmPassword,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: () => _submitPasswordUpdate(isUsingOtp: false),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Save New Password',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                ]

                // View 2: Request Email Form
                else if (_step == ResetStep.requestEmail) ...[
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Registered Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _sendResetLink,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Send Reset Link',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                ]

                // View 3: Link Sent Instructions + Optional Manual Code entry
                else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Colors.orange,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.touch_app_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Tap the link in your email',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Open the email from Jaldi on this device and tap the "Reset Password" button. This app will automatically open to let you set your new password.',
                          style: TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Resend or Change Email Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _step = ResetStep.requestEmail;
                            _showManualOtp = false;
                            _error = null;
                            _infoMessage = null;
                          });
                        },
                        child: const Text('Change Email'),
                      ),
                      TextButton(
                        onPressed: _resendCountdown > 0 ? null : _sendResetLink,
                        child: Text(
                          _resendCountdown > 0
                              ? 'Resend in ${_resendCountdown}s'
                              : 'Resend Link',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Optional OTP Manual Entry toggle
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _showManualOtp = !_showManualOtp);
                    },
                    icon: Icon(
                      _showManualOtp
                          ? Icons.keyboard_arrow_up
                          : Icons.pin_outlined,
                      size: 18,
                    ),
                    label: Text(
                      _showManualOtp
                          ? 'Hide Code Entry'
                          : 'Have a 6-digit code? Enter code manually',
                    ),
                  ),

                  // Manual OTP and Password fields
                  if (_showManualOtp) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _otpController,
                      keyboardType: TextInputType.text,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: '6-digit Code or Reset Link',
                        hintText: 'e.g. 123456 or paste link',
                        prefixIcon: Icon(Icons.pin_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _newPasswordController,
                      obscureText: _obscureNewPassword,
                      decoration: InputDecoration(
                        labelText: 'New Password (min 6 chars)',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureNewPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscureNewPassword = !_obscureNewPassword,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      decoration: InputDecoration(
                        labelText: 'Confirm New Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirmPassword = !_obscureConfirmPassword,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            onPressed: () => _submitPasswordUpdate(isUsingOtp: true),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'Verify Code & Update Password',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                  ],
                ],

                const SizedBox(height: 20),
                // Return to Sign In
                TextButton.icon(
                  onPressed: () {
                    ref.read(authRouterNotifierProvider).clearRecovery();
                    context.go('/auth');
                  },
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Back to Sign In'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
