import 'package:http/http.dart' as http;
import 'package:todo_app/settings/api_config.dart';

/// Wakes the server at launch, while the user is still looking at the screen.
///
/// Render's free tier sleeps after 15 idle minutes and takes about a minute to
/// come back; the first real request would otherwise pay for it. `/health`
/// needs no token and, by design, does not touch the database, so Neon is left
/// asleep until there is something to sync. Fire and forget: the answer does
/// not matter, and a failure here is the ordinary "no connection".
void warmUpServer({http.Client? client, String baseUrl = apiBaseUrl}) {
  final c = client ?? http.Client();
  c
      .get(Uri.parse('$baseUrl/health'))
      .timeout(const Duration(seconds: 70))
      .then<void>((_) {}, onError: (Object _) {})
      .whenComplete(() {
        if (client == null) c.close();
      });
}
