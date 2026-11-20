import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// On the web, sign-in lives on the Kontena website (/login and /signup, same domain), which
/// hands the person back into this app already signed in. On phones the in-app screens are used.
void goAuth(BuildContext context, {bool signUp = false, String? next}) {
  if (kIsWeb) {
    final q = next == null ? '' : '?next=${Uri.encodeQueryComponent(next)}';
    launchUrl(Uri.parse('/${signUp ? 'signup' : 'login'}$q'), webOnlyWindowName: '_self');
  } else {
    context.go('/auth?mode=${signUp ? 'signup' : 'login'}');
  }
}
