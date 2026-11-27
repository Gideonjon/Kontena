import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/api.dart';
import 'ui.dart';

/// Lets the user pick photos, uploads them, and returns storage keys. Returns [] if cancelled or failed.
Future<List<String>> pickAndUploadImages(BuildContext context, {bool multi = false}) async {
  final picker = ImagePicker();
  final List<XFile> files;
  try {
    files = multi ? await picker.pickMultiImage(imageQuality: 80, maxWidth: 1600) : [if (await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600) case final f?) f];
  } catch (_) {
    if (context.mounted) toast(context, 'Could not open your photos.');
    return [];
  }
  final keys = <String>[];
  for (final f in files) {
    final bytes = await f.readAsBytes();
    var type = f.mimeType ?? 'image/jpeg';
    if (!['image/jpeg', 'image/png', 'image/webp'].contains(type)) type = 'image/jpeg';
    if (!context.mounted) return keys;
    final k = await guarded(context, () => Api.i.upload(bytes, type));
    if (k != null) keys.add(k);
  }
  return keys;
}

bool isVideoKey(String k) {
  final l = k.toLowerCase();
  return l.endsWith('.mp4') || l.endsWith('.mov') || l.endsWith('.webm');
}

/// Picks one short video (about a minute), uploads it and returns its storage key. Returns null if cancelled or failed.
Future<String?> pickAndUploadVideo(BuildContext context) async {
  XFile? f;
  try {
    f = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 1));
  } catch (_) {
    if (context.mounted) toast(context, 'Could not open your videos.');
    return null;
  }
  if (f == null) return null;
  final bytes = await f.readAsBytes();
  if (bytes.length > 50 * 1024 * 1024) {
    if (context.mounted) toast(context, 'That video is too large. Keep it under 1 minute.');
    return null;
  }
  final name = f.name.toLowerCase();
  final type = name.endsWith('.mov') ? 'video/quicktime' : name.endsWith('.webm') ? 'video/webm' : 'video/mp4';
  if (!context.mounted) return null;
  return guarded(context, () => Api.i.upload(bytes, type));
}
