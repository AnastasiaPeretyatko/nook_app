/// Where the app's Supabase project lives.
///
/// The key is a **publishable** key and is meant to be here in the open: what
/// guards the data is row-level security on the server, not the secrecy of this
/// string. Supabase's own documentation lists a source repository as a safe
/// place for it. The *secret* key (`sb_secret_…` / `service_role`) bypasses RLS
/// and must never reach the app.
///
/// Plain constants rather than `String.fromEnvironment`: there is no secret to
/// keep out of the build, and a missing `--dart-define` yields `''` silently —
/// every IDE run configuration and every test file would have to be taught the
/// flag. If a second project (staging) ever appears, each constant becomes
/// `String.fromEnvironment('…', defaultValue: <the literal below>)` and nothing
/// else changes.
library;

const supabaseUrl = 'https://gpbmodkzfquyxtujnibv.supabase.co';
const supabasePublishableKey = 'sb_publishable_jbfl4Wgaymwe_2taEzi8Ng_ukebzRO_';

/// Where Supabase sends the browser back after an OAuth sign-in.
///
/// Reverse-DNS, and deliberately not derived from the Android `applicationId`
/// (`com.yourname.todo_app`): a URI scheme may hold only letters, digits, `+`,
/// `-` and `.` (RFC 3986), so the underscore rules that one out, and Android
/// silently fails to match an intent filter whose scheme is invalid. A bare
/// `nook://` would be worse still — any other app may claim a one-word scheme.
///
/// The same string is spelled out in two manifests, which cannot import it:
/// the `<data android:scheme=…>` of the deep-link intent filter in
/// `android/app/src/main/AndroidManifest.xml`, and `CFBundleURLSchemes` in
/// `ios/Runner/Info.plist`. It also has to be listed, character for character,
/// under Redirect URLs in the Supabase dashboard — the matcher there is a glob
/// and is sensitive to a trailing slash. Change it in four places or not at
/// all, and rebuild: a manifest edit does not survive a hot reload.
const authRedirectUrl = 'io.supabase.nook://login-callback';

/// Whether the constants above look like a project at all.
///
/// Cheap sanity, not validation: a blanked-out or half-pasted pair would
/// otherwise fail inside `Supabase.initialize` at a moment when nothing can
/// report it. Failing here instead leaves the account screen saying "server
/// unavailable" and the rest of the app untouched.
bool get supabaseConfigured =>
    supabaseUrl.startsWith('https://') && supabasePublishableKey.isNotEmpty;
