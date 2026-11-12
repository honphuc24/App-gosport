import 'package:flutter/material.dart';
import 'package:gosport/football_api_service.dart';

class SampleMatchDataSource implements MatchDataSource {
  static const _todayMatches = <Match>[
    Match(
      home: 'Manchester City',
      away: 'Real Madrid',
      homeCode: 'MCI',
      awayCode: 'RMA',
      competition: 'UEFA Champions League',
      time: '02:00',
      status: MatchStatus.live,
      homeColor: Color(0xFF6CABDD),
      awayColor: Color(0xFFF4F4F4),
      homeScore: 2,
      awayScore: 1,
      minute: '67’',
    ),
    Match(
      home: 'Arsenal',
      away: 'Bayern Munich',
      homeCode: 'ARS',
      awayCode: 'BAY',
      competition: 'UEFA Champions League',
      time: '02:00',
      status: MatchStatus.live,
      homeColor: Color(0xFFE5323B),
      awayColor: Color(0xFFD71920),
      homeScore: 1,
      awayScore: 1,
      minute: '52’',
    ),
    Match(
      home: 'Liverpool',
      away: 'Tottenham',
      homeCode: 'LIV',
      awayCode: 'TOT',
      competition: 'Premier League',
      time: '21:30',
      status: MatchStatus.upcoming,
      homeColor: Color(0xFFC8102E),
      awayColor: Color(0xFFFFFFFF),
    ),
    Match(
      home: 'Barcelona',
      away: 'Atlético Madrid',
      homeCode: 'BAR',
      awayCode: 'ATM',
      competition: 'La Liga',
      time: '23:00',
      status: MatchStatus.upcoming,
      homeColor: Color(0xFF004D98),
      awayColor: Color(0xFFCB3524),
    ),
    Match(
      home: 'Chelsea',
      away: 'Newcastle',
      homeCode: 'CHE',
      awayCode: 'NEW',
      competition: 'Premier League',
      time: '20:00',
      status: MatchStatus.finished,
      homeColor: Color(0xFF034694),
      awayColor: Color(0xFF241F20),
      homeScore: 2,
      awayScore: 0,
    ),
  ];

  static const _laterMatches = <Match>[
    Match(
      home: 'Manchester United',
      away: 'Aston Villa',
      homeCode: 'MUN',
      awayCode: 'AVL',
      competition: 'Premier League',
      time: '22:30',
      status: MatchStatus.upcoming,
      homeColor: Color(0xFFDA291C),
      awayColor: Color(0xFF670E36),
    ),
    Match(
      home: 'Inter Milan',
      away: 'AC Milan',
      homeCode: 'INT',
      awayCode: 'MIL',
      competition: 'Serie A',
      time: '01:45',
      status: MatchStatus.upcoming,
      homeColor: Color(0xFF00529F),
      awayColor: Color(0xFFFB090B),
    ),
  ];

  @override
  Future<List<Match>> matchesFor(DateTime date) async {
    final today = DateUtils.dateOnly(
      DateTime.now().toUtc().add(const Duration(hours: 7)),
    );
    final daysFromToday = DateUtils.dateOnly(date).difference(today).inDays;
    if (daysFromToday == 1) return [_laterMatches.first];
    if (daysFromToday >= 2) return [_laterMatches.last];
    return _todayMatches;
  }
}
