import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Where the pictures a note owns are kept: its cover and everything embedded in
/// its text.
///
/// Files, not database rows. A picture in a BLOB column bloats the database
/// file, defeats VACUUM and forces the driver to pull the whole image into
/// memory to read any field of the row it sits in.
///
/// A note stores the **file name** only. The directory this resolves to is not
/// stable across launches — on iOS the app container carries a UUID that changes
/// on update — so an absolute path written into the database goes dead.
const _directoryName = 'note_images';

Future<Directory> noteImagesDirectory() async {
  final documents = await getApplicationDocumentsDirectory();
  final directory = Directory(p.join(documents.path, _directoryName));
  if (!await directory.exists()) await directory.create(recursive: true);
  return directory;
}

/// Resolved once per app run, for the widgets that draw a note's pictures.
final noteImagesDirectoryProvider = FutureProvider<Directory>((ref) {
  return noteImagesDirectory();
});

/// Absolute path of a stored [name], or null when there is nothing to draw.
String? noteImagePath(Directory? directory, String? name) =>
    (directory == null || name == null) ? null : p.join(directory.path, name);

/// Copies a picked file into [noteImagesDirectory] and returns the name it was
/// given there.
///
/// The picker hands back a path into a cache the system is free to clear, so
/// nothing chosen is safe until it has been copied. The name is a fresh UUID:
/// two notes may well be given the same photograph, and the second must not
/// overwrite the first's copy.
Future<String> copyIntoNoteImages(String sourcePath) async {
  final directory = await noteImagesDirectory();
  final name = '${const Uuid().v4()}${p.extension(sourcePath)}';
  await File(sourcePath).copy(p.join(directory.path, name));
  return name;
}

/// Removes stored pictures by name, ignoring the ones already gone — deletion is
/// cleanup, and a missing file is the state it is trying to reach.
Future<void> deleteNoteImages(Iterable<String> names) async {
  final directory = await noteImagesDirectory();
  for (final name in names) {
    final file = File(p.join(directory.path, name));
    if (await file.exists()) await file.delete();
  }
}

/// The names in a note's `images` column. A row written before the column
/// existed holds nothing at all, which is not JSON — hence the guard.
List<String> decodeImageNames(String? stored) {
  if (stored == null || stored.trim().isEmpty) return const [];
  final decoded = jsonDecode(stored);
  if (decoded is! List) return const [];
  return [for (final name in decoded) if (name is String) name];
}

String encodeImageNames(List<String> names) => jsonEncode(names);
