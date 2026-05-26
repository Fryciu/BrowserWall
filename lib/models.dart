import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

enum PasswordType { text, biometric, pattern }

class TabModel {
  InAppWebViewController? controller;
  String url;
  String title;
  bool loaded;
  bool isPlayingAudio = false;
  bool isIncognito = false;
  TabModel({
    required this.url,
    this.title = "Nowa karta",
    this.loaded = false,
    this.isIncognito = false,
  });
}

enum BlockReason { none, proxy, content, blacklist, timeLimit }

class BlockMatch {
  final String word;
  final String? translation;
  final String token;
  String? detectedLanguage;

  BlockMatch(this.word, this.token, {this.translation, this.detectedLanguage});

  String get displayWord => translation != null ? '$word ($translation)' : word;

  bool get isFuzzyMatch => token != word;
}

enum TimeRuleMode { dailyLimit, timeWindow }

class TimeRule {
  final String domain;
  final TimeRuleMode mode;
  final int dailyLimitMinutes;
  final TimeOfDay windowStart;
  final TimeOfDay windowEnd;
  final List<int> allowedDays;

  const TimeRule({
    required this.domain,
    this.mode = TimeRuleMode.dailyLimit,
    this.dailyLimitMinutes = 30,
    this.windowStart = const TimeOfDay(hour: 8, minute: 0),
    this.windowEnd = const TimeOfDay(hour: 22, minute: 0),
    this.allowedDays = const [],
  });

  factory TimeRule.fromJson(Map<String, dynamic> j) => TimeRule(
        domain: j['domain'] as String,
        mode: TimeRuleMode.values.firstWhere(
          (e) => e.name == j['mode'],
          orElse: () => TimeRuleMode.dailyLimit,
        ),
        dailyLimitMinutes: j['dailyLimitMinutes'] as int? ?? 30,
        windowStart: TimeOfDay(
          hour: j['windowStartH'] as int? ?? 8,
          minute: j['windowStartM'] as int? ?? 0,
        ),
        windowEnd: TimeOfDay(
          hour: j['windowEndH'] as int? ?? 22,
          minute: j['windowEndM'] as int? ?? 0,
        ),
        allowedDays: List<int>.from(j['allowedDays'] ?? []),
      );

  Map<String, dynamic> toJson() => {
        'domain': domain,
        'mode': mode.name,
        'dailyLimitMinutes': dailyLimitMinutes,
        'windowStartH': windowStart.hour,
        'windowStartM': windowStart.minute,
        'windowEndH': windowEnd.hour,
        'windowEndM': windowEnd.minute,
        'allowedDays': allowedDays,
      };

  TimeRule copyWith({
    TimeRuleMode? mode,
    int? dailyLimitMinutes,
    TimeOfDay? windowStart,
    TimeOfDay? windowEnd,
    List<int>? allowedDays,
  }) =>
      TimeRule(
        domain: domain,
        mode: mode ?? this.mode,
        dailyLimitMinutes: dailyLimitMinutes ?? this.dailyLimitMinutes,
        windowStart: windowStart ?? this.windowStart,
        windowEnd: windowEnd ?? this.windowEnd,
        allowedDays: allowedDays ?? this.allowedDays,
      );
}
