import 'dart:convert';
import 'api.dart';
import 'passkey_js_stub.dart' if (dart.library.js_interop) 'passkey_js_web.dart' as pk;

/// Fingerprint / face confirmation (passkeys). No passwords, no seed phrases.
class Passkeys {
  static bool get supported => pk.passkeySupported();

  static Future<String> _ask(Future<String> Function() f, String cancelled) async {
    try {
      return await f();
    } catch (_) {
      throw ApiException(cancelled);
    }
  }

  /// Saves a passkey on this device for the signed-in user.
  static Future<void> enroll({String label = 'This device'}) async {
    if (!supported) throw ApiException('Fingerprint confirmation is available in the Kontena web app on a phone or laptop with a fingerprint or face unlock.');
    final opts = await Api.i.post('/passkeys/register/options');
    final resp = await _ask(() => pk.passkeyCreate(jsonEncode(opts)), 'Fingerprint setup was cancelled.');
    await Api.i.post('/passkeys/register/verify', {'response': jsonDecode(resp), 'label': label});
  }

  /// Asks for the fingerprint or face and returns a short-lived confirmation token for money actions.
  static Future<String> confirm() async {
    if (!supported) throw ApiException('Open Kontena in your browser to confirm with your fingerprint.');
    final opts = await Api.i.post('/passkeys/auth/options');
    final resp = await _ask(() => pk.passkeyGet(jsonEncode(opts)), 'Fingerprint check was cancelled.');
    final r = await Api.i.post('/passkeys/auth/verify', {'response': jsonDecode(resp)});
    return r.s('token');
  }
}
