# Android app and website download

## One-time: create a release key
Do this once and **keep the file and passwords safe**. If you lose the key, you can never ship an update over an installed app.

```
keytool -genkey -v -keystore ~/kontena-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias kontena
```

Then create `app/android/key.properties` (it is git-ignored):

```
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=kontena
storeFile=/Users/YOU/kontena-release.jks
```

## Build and publish
```
bash scripts/build-apk.sh
firebase deploy --only hosting   # only needed when the website itself changed
```
The APK is uploaded to the `kontena-media` R2 bucket and the Worker serves it at `/download/kontena.apk`, which is what the landing page button links to. (Firebase Hosting's free plan rejects `.apk` files, so it cannot host it.) Deploy the Worker once with `cd backend && npx wrangler deploy`. For each new version, raise `version:` in `app/pubspec.yaml` (for example `1.0.1+2`), because Android only updates to a higher build number.

## Before the first public APK
- **Application ID.** It is still `com.example.kontena`. The ID cannot change after people install the app. Pick the final one now (for example `store.kontena.app`), add an Android app with that ID in Firebase (Project settings > Your apps), download the new `google-services.json` into `app/android/app/`, and update `applicationId` in `app/android/app/build.gradle.kts`.
- **Firebase SHA fingerprints.** If you use Google sign-in or phone auth, add the release key's SHA-1 and SHA-256 in Firebase (`keytool -list -v -keystore ~/kontena-release.jks -alias kontena`).
- **Install warning.** Phones show "install unknown apps" and Play Protect prompts for APKs from a website. That is normal for sideloading. Publishing on Google Play removes it.
