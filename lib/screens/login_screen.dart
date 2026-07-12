import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController(text: 'http://');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final success = await ref.read(authProvider.notifier).login(
          _serverUrlController.text.trim(),
          _usernameController.text.trim(),
          _passwordController.text,
        );

    if (!mounted) return;

    if (success) {
      context.go('/home/library');
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Could not connect. Check the server URL and credentials.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppColors.playerGradient,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ---- Logo ----
                    Center(
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.5),
                              blurRadius: 30,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.music_note_rounded,
                          color: Colors.white,
                          size: 44,
                        ),
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 600.ms)
                        .scale(begin: const Offset(0.6, 0.6)),
                    const SizedBox(height: 24),

                    // ---- App name ----
                    Center(
                      child: Text(
                        'Riffhouse',
                        style: GoogleFonts.inter(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          shadows: [
                            Shadow(
                              color: AppColors.primary.withOpacity(0.6),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                      ),
                    ).animate().fadeIn(delay: 200.ms, duration: 600.ms),

                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        'Connect to your Jellyfin server',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ).animate().fadeIn(delay: 300.ms, duration: 600.ms),

                    const SizedBox(height: 40),

                    // ---- Glass card form ----
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.glass,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: AppColors.glassBorder, width: 1),
                          ),
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              // Server URL
                              TextFormField(
                                controller: _serverUrlController,
                                style: const TextStyle(
                                    color: AppColors.textPrimary),
                                keyboardType: TextInputType.url,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: 'Server URL',
                                  hintText: 'http://192.168.1.100:8096',
                                  prefixIcon: Icon(Icons.dns_outlined,
                                      color: AppColors.primary),
                                ),
                                validator: (v) =>
                                    (v == null || v.isEmpty || v == 'http://')
                                        ? 'Enter a valid server URL'
                                        : null,
                              ),
                              const SizedBox(height: 16),

                              // Username
                              TextFormField(
                                controller: _usernameController,
                                style: const TextStyle(
                                    color: AppColors.textPrimary),
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                  prefixIcon: Icon(Icons.person_outlined,
                                      color: AppColors.primary),
                                ),
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'Enter your username'
                                    : null,
                              ),
                              const SizedBox(height: 16),

                              // Password
                              TextFormField(
                                controller: _passwordController,
                                style: const TextStyle(
                                    color: AppColors.textPrimary),
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                      color: AppColors.primary),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: AppColors.textSecondary,
                                    ),
                                    onPressed: () => setState(() =>
                                        _obscurePassword = !_obscurePassword),
                                  ),
                                ),
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'Enter your password'
                                    : null,
                              ),

                              // Error message
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.red.shade900.withOpacity(0.4),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: Colors.red.shade400
                                            .withOpacity(0.5)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline,
                                          color: Colors.redAccent, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: const TextStyle(
                                              color: Colors.redAccent,
                                              fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 24),

                              // Connect button
                              Container(
                                height: 52,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppColors.primary,
                                      AppColors.primaryDark
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.4),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: _isLoading ? null : _connect,
                                    child: Center(
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                valueColor:
                                                    AlwaysStoppedAnimation(
                                                        Colors.white),
                                              ),
                                            )
                                          : Text(
                                              'Connect',
                                              style: GoogleFonts.inter(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ).animate().fadeIn(delay: 400.ms, duration: 700.ms).slideY(
                          begin: 0.2,
                          end: 0,
                          delay: 400.ms,
                          duration: 600.ms,
                        ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
