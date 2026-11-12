import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const footballDataApiKey = String.fromEnvironment('FOOTBALL_DATA_KEY');

enum MatchStatus { live, upcoming, finished, other }

class Match {
  const Match({
    required this.home,
    required this.away,
    required this.homeCode,
    required this.awayCode,
    required this.competition,
    required this.time,
    required this.status,
    required this.homeColor,
    required this.awayColor,
    this.fixtureId,
    this.competitionArea = 'Khác',
    this.competitionCode = '',
    this.competitionEmblem,
    this.kickoffAt,
    this.homeScore,
    this.awayScore,
    this.minute,
  });

  final String home;
  final String away;
  final String homeCode;
  final String awayCode;
  final String competition;
  final String competitionArea;
  final String competitionCode;
  final String? competitionEmblem;
  final DateTime? kickoffAt;
  final String time;
  final MatchStatus status;
  final Color homeColor;
  final Color awayColor;
  final int? fixtureId;
  final int? homeScore;
  final int? awayScore;
  final String? minute;
}

abstract interface class MatchDataSource {
  Future<List<Match>> matchesFor(DateTime date);
}

class MatchDataException implements Exception {
  const MatchDataException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FootballDataService implements MatchDataSource {
  FootballDataService({String apiKey = footballDataApiKey, http.Client? client})
    : _apiKey = apiKey.trim(),
      _client = client ?? http.Client(),
      _ownsClient = client == null;

  final String _apiKey;
  final http.Client _client;
  final bool _ownsClient;
  final Map<String, _CachedResponse> _responseCache = {};
  final Map<String, Future<Map<String, dynamic>>> _pendingRequests = {};
  DateTime? _rateLimitedUntil;

  static const _cacheDuration = Duration(seconds: 30);
  static const _defaultRateLimitDuration = Duration(minutes: 1);

  @override
  Future<List<Match>> matchesFor(DateTime date) async {
    final selectedDate = DateUtils.dateOnly(date);
    final rows = await _getRows('/matches', 'matches', {
      'dateFrom': _dateText(selectedDate.subtract(const Duration(days: 1))),
      'dateTo': _dateText(selectedDate),
    });
    return rows
        .where((row) {
          final utcDate = DateTime.tryParse(_string(row['utcDate'], ''));
          if (utcDate == null) return true;
          final vietnamDate = utcDate.toUtc().add(const Duration(hours: 7));
          return DateUtils.isSameDay(vietnamDate, selectedDate);
        })
        .map(_matchFromRow)
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  Future<List<Map<String, dynamic>>> searchLeagues(String query) async {
    final rows = await _getRows('/competitions', 'competitions', {});
    final normalizedQuery = query.trim().toLowerCase();
    return rows
        .where((row) {
          final area = _object(row['area']);
          return [
            row['name'],
            row['code'],
            row['type'],
            area['name'],
            area['code'],
          ].any(
            (value) =>
                value is String &&
                value.toLowerCase().contains(normalizedQuery),
          );
        })
        .map(_normalizeCompetition)
        .toList();
  }

  Future<List<Map<String, dynamic>>> competitionTeams(
    String competitionCode,
  ) async {
    final rows = await _getRows(
      '/competitions/${Uri.encodeComponent(competitionCode)}/teams',
      'teams',
      {},
    );
    return rows.map((team) {
      final area = _object(team['area']);
      return {
        'team': {
          'id': team['id'],
          'name': team['name'],
          'code': team['tla'],
          'country': area['name'],
          'crest': team['crest'],
        },
      };
    }).toList();
  }

  Future<List<Match>> competitionMatches({
    required String competitionCode,
    required int season,
  }) async {
    final rows = await _getRows(
      '/competitions/${Uri.encodeComponent(competitionCode)}/matches',
      'matches',
      {'season': '$season'},
    );
    return rows.map(_matchFromRow).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  Future<List<Map<String, dynamic>>> leagueStandings({
    required String leagueCode,
    required int season,
  }) async {
    final rows = await _getRows(
      '/competitions/${Uri.encodeComponent(leagueCode)}/standings',
      'standings',
      {'season': '$season'},
    );
    return rows.expand((group) {
      final table = group['table'];
      if (table is! List) return <Map<String, dynamic>>[];
      return table.whereType<Map<String, dynamic>>().map((row) {
        final team = _object(row['team']);
        return {
          'rank': row['position'],
          'points': row['points'],
          'goalsDiff': row['goalDifference'],
          'team': {'name': team['name']},
          'all': {'played': row['playedGames']},
          'form': row['form'],
          'won': row['won'],
          'draw': row['draw'],
          'lost': row['lost'],
        };
      });
    }).toList();
  }

  Future<List<Map<String, dynamic>>> topScorers({
    required String leagueCode,
    required int season,
  }) async {
    final rows = await _getRows(
      '/competitions/${Uri.encodeComponent(leagueCode)}/scorers',
      'scorers',
      {'season': '$season'},
    );
    return rows.map((row) {
      final player = _object(row['player']);
      final team = _object(row['team']);
      return {
        'player': {'name': player['name']},
        'statistics': [
          {
            'team': {'name': team['name']},
            'goals': {'total': row['goals'], 'assists': row['assists']},
            'games': {'appearences': row['playedMatches']},
          },
        ],
      };
    }).toList();
  }

  Future<List<Match>> teamFixtures({
    required int teamId,
    required int season,
  }) async {
    final rows = await _getRows('/teams/$teamId/matches', 'matches', {
      'season': '$season',
    });
    return rows.map(_matchFromRow).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  Future<Map<String, dynamic>> matchDetails(int fixtureId) async {
    final row = await _getObject('/matches/$fixtureId');
    final events = <Map<String, dynamic>>[];
    final goals = row['goals'];
    if (goals is List) {
      for (final goal in goals.whereType<Map<String, dynamic>>()) {
        final scorer = _object(goal['scorer']);
        final team = _object(goal['team']);
        final minute = goal['minute'];
        final injuryTime = goal['injuryTime'];
        events.add({
          'type': 'Bàn thắng',
          'detail': goal['type'] ?? 'Bàn thắng',
          'team': {'name': team['name']},
          'player': {'name': scorer['name']},
          'time': {'elapsed': minute, 'extra': injuryTime},
        });
      }
    }
    final bookings = row['bookings'];
    if (bookings is List) {
      for (final booking in bookings.whereType<Map<String, dynamic>>()) {
        final player = _object(booking['player']);
        final team = _object(booking['team']);
        events.add({
          'type': 'Thẻ',
          'detail': booking['card'],
          'team': {'name': team['name']},
          'player': {'name': player['name']},
          'time': {'elapsed': booking['minute']},
        });
      }
    }
    final substitutions = row['substitutions'];
    if (substitutions is List) {
      for (final substitution
          in substitutions.whereType<Map<String, dynamic>>()) {
        final playerOut = _object(substitution['playerOut']);
        final playerIn = _object(substitution['playerIn']);
        final team = _object(substitution['team']);
        events.add({
          'type': 'Thay người',
          'detail':
              '${_string(playerOut['name'], 'Cầu thủ')} → '
              '${_string(playerIn['name'], 'Cầu thủ')}',
          'team': {'name': team['name']},
          'player': {'name': playerIn['name']},
          'time': {'elapsed': substitution['minute']},
        });
      }
    }
    events.sort(
      (a, b) => (_intOrNull(_object(a['time'])['elapsed']) ?? 0).compareTo(
        _intOrNull(_object(b['time'])['elapsed']) ?? 0,
      ),
    );
    return {
      'fixture': row,
      'events': events,
      'lineups': <Map<String, dynamic>>[],
      'statistics': <Map<String, dynamic>>[],
    };
  }

  Future<List<Map<String, dynamic>>> _getRows(
    String path,
    String responseKey,
    Map<String, String> parameters,
  ) async {
    final result = await _getObject(path, parameters: parameters);
    final rows = result[responseKey];
    if (rows is! List) {
      throw const MatchDataException(
        'API football-data.org trả dữ liệu không hợp lệ.',
      );
    }
    return rows.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> _getObject(
    String path, {
    Map<String, String> parameters = const {},
  }) async {
    final uri = Uri.https('api.football-data.org', '/v4$path', parameters);
    final requestKey = uri.toString();
    final now = DateTime.now();
    final cached = _responseCache[requestKey];
    if (cached != null && cached.expiresAt.isAfter(now)) {
      return cached.value;
    }
    final pending = _pendingRequests[requestKey];
    if (pending != null) return pending;

    final rateLimitedUntil = _rateLimitedUntil;
    if (rateLimitedUntil != null && rateLimitedUntil.isAfter(now)) {
      final secondsRemaining = rateLimitedUntil.difference(now).inSeconds + 1;
      throw MatchDataException(
        'API đang giới hạn yêu cầu. Vui lòng chờ khoảng '
        '$secondsRemaining giây rồi thử lại.',
      );
    }

    final request = _fetchObject(uri);
    _pendingRequests[requestKey] = request;
    try {
      final value = await request;
      _responseCache[requestKey] = _CachedResponse(
        value,
        DateTime.now().add(_cacheDuration),
      );
      return value;
    } finally {
      if (identical(_pendingRequests[requestKey], request)) {
        _pendingRequests.remove(requestKey);
      }
    }
  }

  Future<Map<String, dynamic>> _fetchObject(Uri uri) async {
    late final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {if (_apiKey.isNotEmpty) 'X-Auth-Token': _apiKey})
          .timeout(const Duration(seconds: 15));
    } on Exception catch (error) {
      throw MatchDataException('Không thể kết nối football-data.org: $error');
    }
    if (response.statusCode != 200) {
      if (response.statusCode == 429) {
        final retryAfter = _retryAfter(response.headers['retry-after']);
        _rateLimitedUntil = DateTime.now().add(retryAfter);
        throw MatchDataException(
          'Đã vượt giới hạn yêu cầu API. Vui lòng thử lại sau '
          '${retryAfter.inSeconds} giây.',
        );
      }
      final apiMessage = _errorMessageFrom(response.body);
      final message = switch (response.statusCode) {
        400 =>
          apiMessage == null
              ? 'Yêu cầu API không hợp lệ hoặc dữ liệu không có trong gói.'
              : 'football-data.org từ chối yêu cầu: $apiMessage',
        403 =>
          apiMessage == null
              ? 'API key không hợp lệ hoặc gói dịch vụ không cho phép endpoint này.'
              : 'football-data.org từ chối API key: $apiMessage',
        _ =>
          'football-data.org trả về lỗi HTTP ${response.statusCode}'
              '${apiMessage == null ? '.' : ': $apiMessage'}',
      };
      throw MatchDataException(message);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const MatchDataException('Dữ liệu trả về từ API không hợp lệ.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const MatchDataException('Dữ liệu trả về từ API không hợp lệ.');
    }
    return decoded;
  }

  String? _errorMessageFrom(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'];
        if (message is String && message.trim().isNotEmpty) {
          final trimmed = message.trim();
          return trimmed.length > 300
              ? '${trimmed.substring(0, 300)}...'
              : trimmed;
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Duration _retryAfter(String? value) {
    if (value != null) {
      final seconds = int.tryParse(value);
      if (seconds != null && seconds > 0) {
        return Duration(seconds: seconds);
      }
      final retryAt = DateTime.tryParse(value);
      if (retryAt != null) {
        final delay = retryAt.difference(DateTime.now());
        if (delay > Duration.zero) return delay;
      }
    }
    return _defaultRateLimitDuration;
  }

  Map<String, dynamic> _normalizeCompetition(Map<String, dynamic> row) {
    final area = _object(row['area']);
    final currentSeason = _object(row['currentSeason']);
    final seasonYear = int.tryParse(
      _string(currentSeason['startDate'], '').split('-').first,
    );
    return {
      'league': {
        'id': row['id'],
        'name': row['name'],
        'country': area['name'],
        'code': row['code'],
        'emblem': row['emblem'],
        'seasons': [
          if (seasonYear != null) {'year': seasonYear, 'current': true},
        ],
      },
    };
  }

  Match _matchFromRow(Map<String, dynamic> row) {
    final competition = _object(row['competition']);
    final area = _object(competition['area']);
    final home = _object(row['homeTeam']);
    final away = _object(row['awayTeam']);
    final score = _object(row['score']);
    final fullTime = _object(score['fullTime']);
    final current = _object(score['regularTime']);
    final utcDate = DateTime.tryParse(_string(row['utcDate'], ''));
    final localDate = utcDate?.toUtc().add(const Duration(hours: 7));
    final status = _statusFromCode(_string(row['status'], ''));
    final homeName = _string(home['name'], 'Đội nhà');
    final awayName = _string(away['name'], 'Đội khách');

    return Match(
      fixtureId: _intOrNull(row['id']),
      home: homeName,
      away: awayName,
      homeCode: _string(home['tla'], _teamCode(homeName)),
      awayCode: _string(away['tla'], _teamCode(awayName)),
      competition: _string(competition['name'], 'Giải đấu'),
      competitionArea: _string(area['name'], 'Khác'),
      competitionCode: _string(competition['code']),
      competitionEmblem: _string(competition['emblem']).isEmpty
          ? null
          : _string(competition['emblem']),
      kickoffAt: utcDate?.toUtc(),
      time: localDate == null
          ? '--:--'
          : '${localDate.hour.toString().padLeft(2, '0')}:'
                '${localDate.minute.toString().padLeft(2, '0')}',
      status: status,
      homeColor: _teamColor(home['id']),
      awayColor: _teamColor(away['id']),
      homeScore: _intOrNull(fullTime['home'] ?? current['home']),
      awayScore: _intOrNull(fullTime['away'] ?? current['away']),
    );
  }

  MatchStatus _statusFromCode(String code) {
    if (const {'IN_PLAY', 'PAUSED', 'LIVE'}.contains(code)) {
      return MatchStatus.live;
    }
    if (const {'FINISHED', 'AWARDED'}.contains(code)) {
      return MatchStatus.finished;
    }
    if (const {
      'SCHEDULED',
      'TIMED',
      'POSTPONED',
      'SUSPENDED',
      'CANCELLED',
    }.contains(code)) {
      return MatchStatus.upcoming;
    }
    return MatchStatus.other;
  }

  String _dateText(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> _object(Object? value) =>
      value is Map<String, dynamic> ? value : const {};

  String _string(Object? value, [String fallback = '']) =>
      value is String && value.isNotEmpty ? value : fallback;

  int? _intOrNull(Object? value) => value is num ? value.toInt() : null;

  String _teamCode(String name) => name
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(3)
      .map((word) => word[0])
      .join()
      .toUpperCase();

  Color _teamColor(Object? id) {
    const palette = [
      Color(0xFF6CABDD),
      Color(0xFFE5323B),
      Color(0xFFB8F36B),
      Color(0xFFD71920),
      Color(0xFF004D98),
      Color(0xFFDA291C),
    ];
    return palette[id is num ? id.toInt().abs() % palette.length : 0];
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class _CachedResponse {
  const _CachedResponse(this.value, this.expiresAt);

  final Map<String, dynamic> value;
  final DateTime expiresAt;
}
