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

  /// Asks the server-side GPT planner for quests and imports them.
  Future<AiPlan> generateQuests({String week = 'auto', String focus = ''});
}

class AiPlan {
  AiPlan.fromJson(Map<String, dynamic> j)
    : count = (j['count'] as num?)?.toInt() ?? 0,
      periodStart = j['period_start'] as String? ?? '',
      titles = List<String>.from(j['titles'] as List? ?? const []);
  final int count;
  final String periodStart;
  final List<String> titles;
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

  @override
  Future<AiPlan> generateQuests({
    String week = 'auto',
    String focus = '',
  }) async {
    final response = await client.functions.invoke(
      'generate-quests',
      body: {'week': week, 'focus': focus},
    );
    return AiPlan.fromJson(Map<String, dynamic>.from(response.data as Map));
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

  @override
  Future<AiPlan> generateQuests({String week = 'auto', String focus = ''}) =>
      throw StateError('Sign in to generate quests with AI.');
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

  Future<AiPlan> generate({String week = 'auto', String focus = ''}) async {
    final plan = await ref
        .read(repositoryProvider)
        .generateQuests(week: week, focus: focus);
    ref.invalidateSelf();
    return plan;
  }
}

String friendlyError(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is AuthException) return error.message;
  if (error is FunctionException) {
    final details = error.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    return 'The quest planner is unavailable right now. Try again soon.';
  }
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

/// A ready-to-paste ChatGPT prompt for players who use their ChatGPT
/// subscription instead of the API. The answer goes back into paste import.
String chatGptPrompt(GameSnapshot game) {
  final today = DateTime.parse(game.today);
  final monday = today.subtract(Duration(days: today.weekday - 1));
  final start = today.weekday == DateTime.sunday
      ? monday.add(const Duration(days: 7))
      : monday;
  String day(DateTime d) => d.toIso8601String().substring(0, 10);
  final first = start.isAfter(today) ? start : today;
  final last = start.add(const Duration(days: 6));
  final tz = game.profile['timezone'];
  final pending = game.quests
      .where((q) => q.status == 'pending')
      .take(30)
      .map((q) => '- ${q.title} (due ${q.dueDate})')
      .join('\n');
  final fixed = game.templates
      .map((t) => '- ${t['title']} (${t['cadence']})')
      .join('\n');
  final habits = game.habits.map((h) => '- ${h.title}').join('\n');
  return '''You are my Life RPG quest planner. Plan quests for the week of ${day(start)} (time zone $tz) across Health, Mind, Craft, Social and Wealth.

Rules:
- Return ONLY one JSON object, no Markdown, no commentary.
- Keys: schema_version (1), period_type ("weekly"), period_start ("${day(start)}"), timezone ("$tz"), quests (array of 4 to 12).
- Every quest has exactly: item_key (unique lowercase slug), title (max 120 chars), description, stat_tag (health|mind|craft|social|wealth), cadence (daily|weekly), difficulty (integer 1-3), estimated_minutes (integer 5-240), due_local_date (YYYY-MM-DD between ${day(first)} and ${day(last)}).
- Total estimated_minutes must stay within the budget in my review below.
- Do not duplicate my fixed responsibilities, habits or pending quests. No XP, gold or status fields.

My weekly review:
${game.review['export_text']}

Fixed responsibilities:
${fixed.isEmpty ? '(none)' : fixed}

Habits:
${habits.isEmpty ? '(none)' : habits}

Pending quests:
${pending.isEmpty ? '(none)' : pending}''';
}
