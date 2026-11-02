import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'domain.dart';
import 'preview.dart';

abstract class GameRepository {
  bool get isPreview;
  Future<GameSnapshot> load();
  Future<void> act(String action, Map<String, dynamic> args);
}

class SupabaseGameRepository implements GameRepository {
  SupabaseGameRepository(this.client);
  final SupabaseClient client;
  @override
  bool get isPreview => false;
  @override
  Future<GameSnapshot> load() async => GameSnapshot.fromJson(
    Map<String, dynamic>.from(
      await client.rpc(
        'life_rpg',
        params: {'action': 'snapshot', 'args': <String, dynamic>{}},
      ) as Map,
    ),
  );
  @override
  Future<void> act(String action, Map<String, dynamic> args) async {
    await client.rpc('life_rpg', params: {'action': action, 'args': args});
  }
}

class PreviewRepository implements GameRepository {
  @override
  bool get isPreview => true;
  @override
  Future<GameSnapshot> load() async => GameSnapshot.fromJson(previewData());
  @override
  Future<void> act(String action, Map<String, dynamic> args) async {
    throw StateError(
      'Sign in to save your adventure. This is a read-only preview.',
    );
  }
}

final repositoryProvider = Provider<GameRepository>(
  (ref) => PreviewRepository(),
);
final gameProvider = AsyncNotifierProvider<GameController, GameSnapshot>(
  GameController.new,
);

class GameController extends AsyncNotifier<GameSnapshot> {
  @override
  Future<GameSnapshot> build() => ref.watch(repositoryProvider).load();

  Future<void> refresh() async {
    // Keep the existing screen visible if a refresh fails.
    final value = await ref.read(repositoryProvider).load();
    state = AsyncData(value);
  }

  Future<void> act(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async {
    await ref.read(repositoryProvider).act(action, args);
    // A successful mutation stays successful even if the follow-up read fails.
    ref.invalidateSelf();
  }
}

String friendlyError(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is AuthException) return error.message;
  if (error is FormatException) {
    return 'That is not valid quest JSON. Check the format and try again.';
  }
  if (error is StateError) return error.message.toString();
  return 'Could not reach your adventure. Check your connection and try again.';
}

Map<String, dynamic> parseQuestBatch(String source) {
  final decoded = jsonDecode(source.trim());
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Expected a quest batch object.');
  }
  if (decoded['schema_version'] != 1 || decoded['quests'] is! List) {
    throw const FormatException('Expected schema_version 1 and quests.');
  }
  return decoded;
}
