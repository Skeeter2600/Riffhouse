import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final service = ref.watch(jellyfinServiceProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ---- Server ----
          _SectionHeader(title: 'Server'),
          _SettingsTile(
            icon: Icons.dns_rounded,
            title: 'Server URL',
            subtitle: service?.serverUrl ?? 'Not connected',
          ),
          _SettingsTile(
            icon: Icons.person_rounded,
            title: 'Username',
            subtitle: user?.name ?? 'Unknown',
          ),
          _DangerTile(
            icon: Icons.logout_rounded,
            title: 'Disconnect',
            subtitle: 'Sign out from this server',
            onTap: () => _confirmLogout(context, ref),
          ),

          const SizedBox(height: 8),

          // ---- Playback ----
          _SectionHeader(title: 'Playback'),
          _ToggleTile(
            icon: Icons.music_note_rounded,
            title: 'Gapless Playback',
            subtitle: 'Seamless transitions between tracks',
            value: true,
            onChanged: (_) {},
          ),
          _ToggleTile(
            icon: Icons.blur_on_rounded,
            title: 'Crossfade',
            subtitle: 'Fade between tracks (2 s)',
            value: false,
            onChanged: (_) {},
          ),

          const SizedBox(height: 8),

          // ---- Cache ----
          _SectionHeader(title: 'Cache'),
          _SettingsTile(
            icon: Icons.storage_rounded,
            title: 'Downloads',
            subtitle: 'Manage offline tracks',
            onTap: () => context.push('/home/downloads'),
          ),
          _DangerTile(
            icon: Icons.delete_outline,
            title: 'Clear Cache',
            subtitle: 'Remove all downloaded files',
            onTap: () => _confirmClearCache(context, ref),
          ),

          const SizedBox(height: 8),

          // ---- About ----
          _SectionHeader(title: 'About'),
          _SettingsTile(
            icon: Icons.info_outline_rounded,
            title: 'Version',
            subtitle: '1.0.0 (build 1)',
          ),
          _SettingsTile(
            icon: Icons.code_rounded,
            title: 'GitHub',
            subtitle: 'github.com/your-repo/riffhouse',
            onTap: () {
              // URL launcher not yet wired; show a snackbar instead.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('https://github.com/your-repo/riffhouse'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Disconnect',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            child: const Text('Disconnect',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmClearCache(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear Cache',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'All offline tracks will be deleted from your device.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Clear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings section widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: const TextStyle(
              color: AppColors.textMuted, fontSize: 12)),
      onTap: onTap,
      trailing: onTap != null
          ? const Icon(Icons.chevron_right, color: AppColors.textMuted)
          : null,
    );
  }
}

class _ToggleTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_ToggleTile> createState() => _ToggleTileState();
}

class _ToggleTileState extends State<_ToggleTile> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(widget.icon, color: AppColors.primary, size: 20),
      ),
      title: Text(widget.title,
          style: const TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
      subtitle: Text(widget.subtitle,
          style: const TextStyle(
              color: AppColors.textMuted, fontSize: 12)),
      trailing: Switch(
        value: _value,
        onChanged: (v) {
          setState(() => _value = v);
          widget.onChanged(v);
        },
        activeColor: AppColors.primary,
      ),
    );
  }
}

class _DangerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DangerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.redAccent, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(
              color: Colors.redAccent, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: const TextStyle(
              color: AppColors.textMuted, fontSize: 12)),
      onTap: onTap,
    );
  }
}
