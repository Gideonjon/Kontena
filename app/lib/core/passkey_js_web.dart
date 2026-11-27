// Web builds: calls window.kontenaPasskey from web/index.html (WebAuthn in the browser).
import 'dart:js_interop';

@JS('kontenaPasskey.supported')
external JSBoolean _supported();
@JS('kontenaPasskey.create')
external JSPromise<JSString> _create(JSString optionsJson);
@JS('kontenaPasskey.get')
external JSPromise<JSString> _get(JSString optionsJson);

bool passkeySupported() {
  try {
    return _supported().toDart;
  } catch (_) {
    return false;
  }
}

Future<String> passkeyCreate(String optionsJson) async => (await _create(optionsJson.toJS).toDart).toDart;
Future<String> passkeyGet(String optionsJson) async => (await _get(optionsJson.toJS).toDart).toDart;
