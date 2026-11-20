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
