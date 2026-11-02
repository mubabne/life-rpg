import 'package:flutter/material.dart';

enum LifeStat {
  health('Health', Icons.favorite_rounded, Color(0xFFFF8B92)),
  mind('Mind', Icons.auto_awesome_rounded, Color(0xFFB9A1FF)),
  craft('Craft', Icons.handyman_rounded, Color(0xFFEDC47A)),
  social('Social', Icons.people_alt_rounded, Color(0xFF83C5EB)),
  wealth('Wealth', Icons.savings_rounded, Color(0xFF95D4AE));

  const LifeStat(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
  static LifeStat parse(String value) =>
      values.firstWhere((s) => s.name == value);
}

class Quest {
  Quest.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String,
      description = j['description'] as String,
      stat = LifeStat.parse(j['stat_tag'] as String),
      cadence = j['cadence'] as String,
      status = j['status'] as String,
      source = j['source'] as String,
      dueDate = j['due_local_date'] as String,
      xp = (j['xp_reward'] as num).toInt(),
      gold = (j['gold_reward'] as num).toInt(),
      minutes = (j['estimated_minutes'] as num).toInt();
  final String id, title, description, cadence, status, source, dueDate;
  final LifeStat stat;
  final int xp, gold, minutes;
  bool get completed => status == 'completed';
}

class Habit {
  Habit.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String,
      stat = LifeStat.parse(j['stat_tag'] as String),
      strength = (j['strength'] as num).toDouble(),
      streak = (j['streak'] as num).toInt(),
      completedToday = j['completed_today'] == true,
      freezesLeft = (j['freezes_left'] as num).toInt(),
      week = List<String>.from(j['week'] as List);
  final String id, title;
  final LifeStat stat;
  final double strength;
  final int streak, freezesLeft;
  final bool completedToday;
  final List<String> week;
}

class GameSnapshot {
  GameSnapshot.fromJson(Map<String, dynamic> j)
    : profile = Map<String, dynamic>.from(j['profile'] as Map),
      progress = Map<String, dynamic>.from(j['progress'] as Map),
      review = Map<String, dynamic>.from(j['review'] as Map),
      stats = Map<String, dynamic>.from(j['stats'] as Map),
      today = j['today'] as String,
      quests = (j['quests'] as List)
          .map((q) => Quest.fromJson(Map<String, dynamic>.from(q as Map)))
          .toList(),
      habits = (j['habits'] as List)
          .map((h) => Habit.fromJson(Map<String, dynamic>.from(h as Map)))
          .toList(),
      templates = List<Map<String, dynamic>>.from(j['templates'] as List),
      imports = List<Map<String, dynamic>>.from(j['imports'] as List? ?? []);
  final Map<String, dynamic> profile, progress, review, stats;
  final String today;
  final List<Quest> quests;
  final List<Habit> habits;
  final List<Map<String, dynamic>> templates;
  final List<Map<String, dynamic>> imports;
  String get name => profile['display_name'] as String;
  int get level => (progress['level'] as num).toInt();
  int get xp => (progress['total_xp'] as num).toInt();
  int get gold => (progress['gold'] as num).toInt();
  double get levelFraction => (progress['level_fraction'] as num).toDouble();
}
