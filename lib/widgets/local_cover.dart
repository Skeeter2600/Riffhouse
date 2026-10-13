import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../services/local_cover_store.dart';

/// Shows the cover saved on this device for [itemId] if there is one, and
/// [child] (the server's artwork) otherwise.
class LocalCoverOr extends ConsumerWidget {
  /// The playlist to look up; null when the item cannot have a local cover.
  final String? itemId;
  final Widget child;

  const LocalCoverOr({super.key, required this.itemId, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = itemId;
    if (id == null) return child;
    final service = ref.watch(musicServiceProvider);

    return ValueListenableBuilder<int>(
      valueListenable: LocalCoverStore.revision,
      builder: (context, _, __) {
        final file = LocalCoverStore.coverFor(service, id);
        if (file == null) return child;
        return Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => child,
        );
      },
    );
  }
}
