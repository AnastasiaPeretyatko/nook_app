/// Where the app's own server lives (the `nook-server` repo, on Render).
///
/// A plain constant: there is no secret in an address, and a missing `--dart-define` would yield `''` silently. Moving
/// to a VPS later means changing this one line and rebuilding.
library;

const apiBaseUrl = 'https://nook-krq9.onrender.com';

/// The Google Cloud **web** client id: the audience of the ID token the phone
/// asks Google for, and the same id the server lists in `GOOGLE_CLIENT_IDS`.
/// Public by design (it is in every token). The Android client — package name
/// plus the SHA-1 of the signing key — is registered in the Google console, not
/// here.
const googleServerClientId =
    '708695856433-lb32mck5fjtkpcolticpdh2mg8n57db8.apps.googleusercontent.com';
