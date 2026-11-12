import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:gosport/football_api_service.dart';
import 'package:gosport/football_features_page.dart';
import 'package:gosport/main.dart';
import 'package:gosport/sample_match_data_source.dart';

void main() {
  testWidgets('selects a league and filters its completed matches', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('Tỷ số hôm nay'), findsOneWidget);
    expect(find.text('Trong trận'), findsWidgets);
    await tester.drag(
      find.byKey(const ValueKey('home-scroll')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    final firstLeagueGroup = find.byType(ExpansionTile).first;
    await tester.ensureVisible(firstLeagueGroup);
    await tester.pumpAndSettle();
    await tester.tap(firstLeagueGroup);
    await tester.pumpAndSettle();
    final premierLeague = find.text('Premier League').first;
    await tester.ensureVisible(premierLeague);
    await tester.pumpAndSettle();
    await tester.tap(premierLeague);
    await tester.pumpAndSettle();
    expect(find.text('Liverpool'), findsOneWidget);
    expect(find.text('Barcelona'), findsNothing);

    await tester.tap(find.text('Sớm').first);
    await tester.pumpAndSettle();

    expect(find.text('Sớm'), findsWidgets);
    expect(find.text('Chelsea'), findsOneWidget);

    await tester.tap(find.text('Giải đấu').first);
    await tester.pumpAndSettle();
    expect(find.text('Liverpool'), findsOneWidget);

    await tester.tap(find.text('Trong trận').first);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('home-scroll')),
      const Offset(0, 800),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Chưa có giải đấu nào có trận trong mục này.'),
      findsOneWidget,
    );
    expect(find.textContaining('Gói Free'), findsOneWidget);
  });

  testWidgets('filters by league and can clear the selection', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('home-scroll')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    final firstLeagueGroup = find.byType(ExpansionTile).first;
    await tester.ensureVisible(firstLeagueGroup);
    await tester.pumpAndSettle();
    await tester.tap(firstLeagueGroup);
    await tester.pumpAndSettle();
    final laLiga = find.text('La Liga').first;
    await tester.ensureVisible(laLiga);
    await tester.pumpAndSettle();
    await tester.tap(laLiga);
    await tester.pumpAndSettle();

    expect(find.text('Barcelona'), findsOneWidget);
    expect(find.text('Liverpool'), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('home-scroll')),
      const Offset(0, 520),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    await tester.ensureVisible(firstLeagueGroup);
    await tester.pumpAndSettle();
    await tester.tap(firstLeagueGroup);
    await tester.pumpAndSettle();

    expect(find.text('Premier League'), findsWidgets);
    expect(find.text('La Liga'), findsWidgets);
    expect(find.text('Barcelona'), findsNothing);
  });

  testWidgets('shows API errors and a retry action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(GoSportApp(dataSource: _MissingKeyDataSource()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Đã vượt giới hạn'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
  });

  testWidgets('shows only leagues that have matches in the live filter', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trong trận').first);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('home-scroll')),
      const Offset(0, 800),
    );
    await tester.pumpAndSettle();

    final leagueGroup = find.byType(ExpansionTile).first;
    await tester.ensureVisible(leagueGroup);
    await tester.pumpAndSettle();
    await tester.tap(leagueGroup);
    await tester.pumpAndSettle();

    expect(find.text('UEFA Champions League'), findsWidgets);
    expect(find.text('Premier League'), findsNothing);
    expect(find.text('La Liga'), findsNothing);
  });

  testWidgets('selects a past date for finished matches', (
    WidgetTester tester,
  ) async {
    final dataSource = _DateTrackingMatchDataSource();
    await tester.pumpWidget(GoSportApp(dataSource: dataSource));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sớm').first);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('home-scroll')),
      const Offset(0, 800),
    );
    await tester.pumpAndSettle();

    final datePickerButton = find.byKey(const ValueKey('pick-results-date'));
    await tester.tap(datePickerButton);
    await tester.pumpAndSettle();
    expect(find.text('Chọn ngày xem trận'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final today = DateUtils.dateOnly(
      DateTime.now().toUtc().add(const Duration(hours: 7)),
    );
    final previousMonth = DateTime(today.year, today.month - 1, 15);
    expect(
      dataSource.requestedDates.any(
        (date) => DateUtils.isSameDay(date, previousMonth),
      ),
      isTrue,
    );
    expect(
      find.text(
        '${_weekdayLabel(previousMonth.weekday)}, 15 THÁNG ${previousMonth.month}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows scheduled matches for a custom future date', (
    WidgetTester tester,
  ) async {
    final dataSource = _DateTrackingMatchDataSource();
    await tester.pumpWidget(GoSportApp(dataSource: dataSource));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sớm').first);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('home-scroll')),
      const Offset(0, 800),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-results-date')));
    await tester.pumpAndSettle();

    final today = DateUtils.dateOnly(
      DateTime.now().toUtc().add(const Duration(hours: 7)),
    );
    var targetDate = DateTime(today.year, today.month, 25);
    if (!targetDate.isAfter(today)) {
      targetDate = DateTime(today.year, today.month + 1, 25);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('25').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(
      dataSource.requestedDates.any(
        (date) => DateUtils.isSameDay(date, targetDate),
      ),
      isTrue,
    );
    await tester.drag(
      find.byKey(const ValueKey('home-scroll')),
      const Offset(0, -800),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('shows sample matches with a visible demo warning', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      GoSportApp(
        dataSource: SampleMatchDataSource(),
        showSampleDataLabel: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DỮ LIỆU MẪU · KHÔNG PHẢI TỶ SỐ THẬT'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('home-scroll')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    final firstLeagueGroup = find.byType(ExpansionTile).first;
    await tester.ensureVisible(firstLeagueGroup);
    await tester.pumpAndSettle();
    await tester.tap(firstLeagueGroup);
    await tester.pumpAndSettle();
    final championsLeague = find.text('UEFA Champions League').first;
    await tester.ensureVisible(championsLeague);
    await tester.pumpAndSettle();
    await tester.tap(championsLeague);
    await tester.pumpAndSettle();
    expect(find.text('Manchester City'), findsOneWidget);
    expect(find.text('67’'), findsOneWidget);
  });

  testWidgets('shows league lists in small batches', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(GoSportApp(dataSource: _ManyLeagueDataSource()));
    await tester.pumpAndSettle();

    final showMoreButton = find.text('Hiện thêm 13 giải đấu');
    expect(showMoreButton, findsOneWidget);
    await tester.ensureVisible(showMoreButton);
    await tester.pumpAndSettle();
    await tester.tap(showMoreButton);
    await tester.pumpAndSettle();

    expect(showMoreButton, findsNothing);
  });

  testWidgets('shows season selector in league overview screen', (
    WidgetTester tester,
  ) async {
    final service = FootballDataService(client: _LeagueOverviewHttpClient());

    await tester.pumpWidget(
      MaterialApp(
        home: LeagueOverviewPage(
          service: service,
          leagueCode: 'PL',
          leagueName: 'Premier League',
          season: 2024,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mùa giải'), findsOneWidget);
    expect(find.text('2024/25'), findsOneWidget);
    expect(find.text('2023/24'), findsOneWidget);
  });

  testWidgets('opens league overview on the selected ranking tab', (
    WidgetTester tester,
  ) async {
    final service = FootballDataService(client: _LeagueOverviewHttpClient());

    await tester.pumpWidget(
      MaterialApp(
        home: LeagueOverviewPage(
          service: service,
          leagueCode: 'PL',
          leagueName: 'Premier League',
          season: 2024,
          initialTab: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Chưa có dữ liệu vua phá lưới cho giải đấu/mùa này.'),
      findsOneWidget,
    );
    expect(
      find.text('Chưa có bảng xếp hạng cho giải đấu/mùa này.'),
      findsNothing,
    );
  });

  testWidgets('shows match tabs and live match view', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('Giải đấu'), findsWidgets);
    expect(find.text('Trong trận'), findsWidgets);
    expect(find.text('Sắp diễn ra'), findsWidgets);
    expect(find.text('Sớm'), findsWidgets);
  });

  testWidgets('shows only working bottom navigation destinations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('Game'), findsNothing);
    expect(find.byIcon(Icons.sports_basketball), findsNothing);
    expect(find.byIcon(Icons.sports_tennis), findsNothing);
    expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);

    await tester.tap(find.text('Tài khoản'));
    await tester.pumpAndSettle();
    expect(find.text('Cần cấu hình Firebase'), findsOneWidget);

    await tester.tap(find.text('Trận'));
    await tester.pumpAndSettle();
    expect(find.text('Manchester City'), findsOneWidget);
    expect(find.text('Trong trận'), findsWidgets);

    await tester.tap(find.text('Thể thao'));
    await tester.pumpAndSettle();
    expect(find.text('Tỷ số hôm nay'), findsOneWidget);
  });

  testWidgets('shows and removes starred matches on the favorites page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Yêu thích'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có trận yêu thích'), findsOneWidget);

    await tester.tap(find.text('Trận'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trong trận').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Manchester City').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.star_outline_rounded).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Yêu thích'));
    await tester.pumpAndSettle();
    expect(find.text('Trận yêu thích'), findsOneWidget);
    expect(find.text('Manchester City'), findsOneWidget);
    expect(find.text('1 trận'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.star_rounded).at(1));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có trận yêu thích'), findsOneWidget);
    expect(find.text('Manchester City'), findsNothing);
  });

  testWidgets('filters upcoming matches by selected time window', (
    WidgetTester tester,
  ) async {
    final dataSource = _UpcomingWindowDataSource();
    await tester.pumpWidget(GoSportApp(dataSource: dataSource));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sắp diễn ra').first);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('popular-leagues-carousel')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('upcoming-window-3')), findsOneWidget);
    expect(find.text('Trong 4 giờ'), findsNothing);
    expect(find.text('Trong 10 giờ'), findsNothing);
    expect(find.text('Trong 18 giờ'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('upcoming-window-6')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Giải kiểm thử').last);
    await tester.pumpAndSettle();
    expect(find.text('Trong 4 giờ'), findsOneWidget);
    expect(find.text('Trong 10 giờ'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('upcoming-window-12')));
    await tester.pumpAndSettle();
    expect(find.text('Trong 4 giờ'), findsOneWidget);
    expect(find.text('Trong 10 giờ'), findsOneWidget);
    expect(find.text('Trong 18 giờ'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('upcoming-window-24')));
    await tester.pumpAndSettle();
    expect(find.text('Trong 18 giờ'), findsOneWidget);
    expect(find.textContaining(' · '), findsWidgets);
  });

  testWidgets('returns to the previous page from match details', (
    WidgetTester tester,
  ) async {
    final service = FootballDataService(client: _LeagueOverviewHttpClient());
    const match = Match(
      fixtureId: 123,
      home: 'Liverpool',
      away: 'Arsenal',
      homeCode: 'LIV',
      awayCode: 'ARS',
      competition: 'Premier League',
      time: '20:00',
      status: MatchStatus.upcoming,
      homeColor: Color(0xFFC8102E),
      awayColor: Color(0xFFEF0107),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        MatchDetailsPage(service: service, match: match),
                  ),
                ),
                child: const Text('Trang trước'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Trang trước'));
    await tester.pumpAndSettle();
    expect(find.text('Chi tiết trận đấu'), findsOneWidget);

    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();

    expect(find.text('Trang trước'), findsOneWidget);
    expect(find.text('Chi tiết trận đấu'), findsNothing);
  });

  testWidgets('explains free-tier live score limits when no live match exists', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(GoSportApp(dataSource: _FinishedOnlyDataSource()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trong trận').first);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Gói Free chưa hỗ trợ tỷ số trực tiếp. Chọn “Giải đấu” để xem lịch và kết quả có độ trễ.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('refreshes match data every minute', (WidgetTester tester) async {
    final dataSource = _CountingMatchDataSource();
    await tester.pumpWidget(GoSportApp(dataSource: dataSource));
    await tester.pumpAndSettle();

    expect(dataSource.requestCount, 1);
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();

    expect(dataSource.requestCount, 2);
  });
}

GoSportApp _testApp() => GoSportApp(dataSource: _FakeMatchDataSource());

class _FinishedOnlyDataSource implements MatchDataSource {
  @override
  Future<List<Match>> matchesFor(DateTime date) async => const [
    Match(
      home: 'Chelsea',
      away: 'Arsenal',
      homeCode: 'CHE',
      awayCode: 'ARS',
      competition: 'Premier League',
      time: '18:00',
      status: MatchStatus.finished,
      homeColor: Color(0xFF034694),
      awayColor: Color(0xFFEF0107),
      homeScore: 2,
      awayScore: 1,
    ),
  ];
}

class _CountingMatchDataSource implements MatchDataSource {
  int requestCount = 0;

  @override
  Future<List<Match>> matchesFor(DateTime date) async {
    requestCount++;
    return const [];
  }
}

class _DateTrackingMatchDataSource implements MatchDataSource {
  final requestedDates = <DateTime>[];

  @override
  Future<List<Match>> matchesFor(DateTime date) async {
    requestedDates.add(date);
    return [
      Match(
        home: 'Home',
        away: 'Away',
        homeCode: 'HOM',
        awayCode: 'AWY',
        competition: 'League',
        time: '19:00',
        kickoffAt: DateTime.utc(date.year, date.month, date.day, 12),
        status: MatchStatus.upcoming,
        homeColor: const Color(0xFF034694),
        awayColor: const Color(0xFFEF0107),
      ),
    ];
  }
}

String _weekdayLabel(int weekday) => const [
  'THỨ 2',
  'THỨ 3',
  'THỨ 4',
  'THỨ 5',
  'THỨ 6',
  'THỨ 7',
  'CHỦ NHẬT',
][weekday - 1];

class _ManyLeagueDataSource implements MatchDataSource {
  @override
  Future<List<Match>> matchesFor(DateTime date) async => List.generate(
    25,
    (index) => Match(
      home: 'Home $index',
      away: 'Away $index',
      homeCode: 'H$index',
      awayCode: 'A$index',
      competition: 'League ${index.toString().padLeft(2, '0')}',
      time: '12:00',
      status: MatchStatus.upcoming,
      homeColor: const Color(0xFF034694),
      awayColor: const Color(0xFFEF0107),
    ),
  );
}

class _UpcomingWindowDataSource implements MatchDataSource {
  _UpcomingWindowDataSource()
    : matches = [4, 10, 18].map((hours) {
        final kickoff = DateTime.now().toUtc().add(Duration(hours: hours));
        final localKickoff = kickoff.add(const Duration(hours: 7));
        return Match(
          home: 'Trong $hours giờ',
          away: 'Đội khách $hours',
          homeCode: 'H$hours',
          awayCode: 'A$hours',
          competition: 'Giải kiểm thử',
          time:
              '${localKickoff.hour.toString().padLeft(2, '0')}:'
              '${localKickoff.minute.toString().padLeft(2, '0')}',
          kickoffAt: kickoff,
          status: MatchStatus.upcoming,
          homeColor: const Color(0xFF034694),
          awayColor: const Color(0xFFEF0107),
        );
      }).toList();

  final List<Match> matches;

  @override
  Future<List<Match>> matchesFor(DateTime date) async => matches.where((match) {
    final matchDate = match.kickoffAt!.toUtc().add(const Duration(hours: 7));
    return DateUtils.isSameDay(matchDate, date);
  }).toList();
}

class _FakeMatchDataSource implements MatchDataSource {
  static const matches = <Match>[
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

  @override
  Future<List<Match>> matchesFor(DateTime date) async => matches;
}

class _MissingKeyDataSource implements MatchDataSource {
  @override
  Future<List<Match>> matchesFor(DateTime date) {
    throw const MatchDataException(
      'Đã vượt giới hạn yêu cầu API. Vui lòng thử lại sau.',
    );
  }
}

class _LeagueOverviewHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonEncode({
      'matches': <Map<String, dynamic>>[],
      'standings': <Map<String, dynamic>>[],
      'scorers': <Map<String, dynamic>>[],
      'teams': <Map<String, dynamic>>[],
    });

    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}
