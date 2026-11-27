// Mobile builds: passkeys run in the web app for now.
bool passkeySupported() => false;
Future<String> passkeyCreate(String optionsJson) => throw UnsupportedError('Passkeys are not available here');
Future<String> passkeyGet(String optionsJson) => throw UnsupportedError('Passkeys are not available here');
