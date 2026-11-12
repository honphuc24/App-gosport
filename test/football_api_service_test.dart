import 'package:flutter_test/flutter_test.dart';
import 'package:gosport/football_api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('requests football-data matches and maps live score data', () async {
    Uri? requestedUri;
    String? requestedKey;
    final service = FootballDataService(
      apiKey: 'test-key',
      client: MockClient((request) async {
        requestedUri = request.url;
        requestedKey = request.headers['x-auth-token'];
        return http.Response('''
          {
            "matches": [{
              "id": 123,
              "utcDate": "2026-10-17T12:30:00Z",
              "status": "IN_PLAY",
              "competition": {"name": "Premier League"},
              "homeTeam": {"id": 1, "name": "Manchester City", "tla": "MCI"},
              "awayTeam": {"id": 2, "name": "Arsenal", "tla": "ARS"},
              "score": {"fullTime": {"home": 2, "away": 1}}
            }, {
              "id": 124,
              "utcDate": "2026-10-17T10:00:00Z",
              "status": "SCHEDULED",
              "competition": {"name": "UEFA Champions League"},
              "homeTeam": {"id": 3, "name": "Arsenal", "tla": "ARS"},
              "awayTeam": {"id": 4, "name": "Real Madrid", "tla": "RMA"},
              "score": {"fullTime": {"home": null, "away": null}}
            }]
          }
          ''', 200);
      }),
    );

    final matches = await service.matchesFor(DateTime(2026, 10, 17));

    expect(requestedUri?.path, '/v4/matches');
    expect(requestedUri?.queryParameters['dateFrom'], '2026-10-16');
    expect(requestedUri?.queryParameters['dateTo'], '2026-10-17');
    expect(requestedUri?.queryParameters.containsKey('competitions'), isFalse);
    expect(requestedKey, 'test-key');
    expect(matches, hasLength(2));
    final liveMatch = matches.singleWhere((match) => match.fixtureId == 123);
    expect(liveMatch.home, 'Manchester City');
    expect(liveMatch.competition, 'Premier League');
    expect(liveMatch.status, MatchStatus.live);
    expect(liveMatch.homeScore, 2);
    expect(liveMatch.awayScore, 1);
    expect(
      matches.map((match) => match.competition),
      containsAll(['Premier League', 'UEFA Champions League']),
    );
  });

  test(
    'includes matches by Vietnam calendar day across UTC midnight',
    () async {
      Uri? requestedUri;
      final service = FootballDataService(
        apiKey: 'test-key',
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response('''
          {"matches": [
            {"id": 1, "utcDate": "2026-10-17T16:30:00Z", "status": "SCHEDULED", "competition": {"name": "League"}, "homeTeam": {"name": "Home"}, "awayTeam": {"name": "Away"}},
            {"id": 2, "utcDate": "2026-10-17T18:30:00Z", "status": "SCHEDULED", "competition": {"name": "League"}, "homeTeam": {"name": "Home"}, "awayTeam": {"name": "Away"}},
            {"id": 3, "utcDate": "2026-10-18T18:30:00Z", "status": "SCHEDULED", "competition": {"name": "League"}, "homeTeam": {"name": "Home"}, "awayTeam": {"name": "Away"}}
          ]}
          ''', 200);
        }),
      );

      final matches = await service.matchesFor(DateTime(2026, 10, 18));

      expect(requestedUri?.queryParameters['dateFrom'], '2026-10-17');
      expect(requestedUri?.queryParameters['dateTo'], '2026-10-18');
      expect(matches, hasLength(1));
      expect(matches.single.time, '01:30');
    },
  );

  test(
    'calls the public endpoint anonymously when no token is configured',
    () async {
      String? requestedKey;
      final service = FootballDataService(
        apiKey: '',
        client: MockClient((request) async {
          requestedKey = request.headers['x-auth-token'];
          return http.Response('{"matches":[]}', 200);
        }),
      );

      final matches = await service.matchesFor(DateTime(2026, 10, 17));

      expect(matches, isEmpty);
      expect(requestedKey, isNull);
    },
  );

  test('caches repeated requests during the cache window', () async {
    var requestCount = 0;
    final service = FootballDataService(
      apiKey: 'test-key',
      client: MockClient((_) async {
        requestCount++;
        return http.Response('{"matches":[]}', 200);
      }),
    );

    await service.matchesFor(DateTime(2026, 10, 17));
    await service.matchesFor(DateTime(2026, 10, 17));

    expect(requestCount, 1);
  });

  test(
    'honors the API retry-after cooldown without sending another request',
    () async {
      var requestCount = 0;
      final service = FootballDataService(
        apiKey: 'test-key',
        client: MockClient((_) async {
          requestCount++;
          return http.Response('{}', 429, headers: {'retry-after': '60'});
        }),
      );

      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          service.matchesFor(DateTime(2026, 10, 17)),
          throwsA(
            isA<MatchDataException>().having(
              (error) => error.message,
              'message',
              contains('60 giây'),
            ),
          ),
        );
      }

      expect(requestCount, 1);
    },
  );

  test('reports authorization and rate limit errors', () async {
    for (final scenario in [
      (code: 403, message: 'API key không hợp lệ'),
      (code: 429, message: 'Đã vượt giới hạn'),
    ]) {
      final service = FootballDataService(
        apiKey: 'test-key',
        client: MockClient((_) async => http.Response('{}', scenario.code)),
      );

      await expectLater(
        service.matchesFor(DateTime(2026, 10, 17)),
        throwsA(
          isA<MatchDataException>().having(
            (error) => error.message,
            'message',
            contains(scenario.message),
          ),
        ),
      );
    }
  });

  test('shows the API error message for invalid requests', () async {
    final service = FootballDataService(
      apiKey: 'test-key',
      client: MockClient(
        (_) async => http.Response(
          '{"message":"The requested resource is not available in your plan."}',
          400,
        ),
      ),
    );

    await expectLater(
      service.matchesFor(DateTime(2026, 10, 17)),
      throwsA(
        isA<MatchDataException>().having(
          (error) => error.message,
          'message',
          contains('The requested resource is not available in your plan.'),
        ),
      ),
    );
  });

  test('loads leagues, standings, scorers, teams and match events', () async {
    final requests = <Uri>[];
    final service = FootballDataService(
      apiKey: 'test-key',
      client: MockClient((request) async {
        requests.add(request.url);
        final body = switch (request.url.path) {
          '/v4/competitions' =>
            '{"competitions":[{"id":2021,"code":"PL","name":"Premier League","area":{"name":"England"},"currentSeason":{"startDate":"2026-08-01","endDate":"2027-05-31"}}]}',
          '/v4/competitions/PL/standings' =>
            '{"standings":[{"table":[{"position":1,"points":90,"goalDifference":55,"playedGames":38,"team":{"name":"Liverpool"}}]}]}',
          '/v4/competitions/PL/scorers' =>
            '{"scorers":[{"player":{"name":"Player"},"team":{"name":"Liverpool"},"playedMatches":30,"goals":20,"assists":4}]}',
          '/v4/competitions/CL/matches' =>
            '{"matches":[{"id":321,"utcDate":"2026-10-17T18:00:00Z","status":"SCHEDULED","competition":{"name":"UEFA Champions League"},"homeTeam":{"name":"Arsenal","tla":"ARS"},"awayTeam":{"name":"Real Madrid","tla":"RMA"},"score":{"fullTime":{"home":null,"away":null}}}]}',
          '/v4/competitions/PL/teams' =>
            '{"teams":[{"id":40,"name":"Liverpool","tla":"LIV","area":{"name":"England"}}]}',
          '/v4/teams/40/matches' => '{"matches":[]}',
          '/v4/matches/123' =>
            '{"id":123,"goals":[{"minute":12,"type":"REGULAR","team":{"name":"Liverpool"},"scorer":{"name":"Player"}}],"bookings":[],"substitutions":[]}',
          _ => '{}',
        };
        return http.Response(body, 200);
      }),
    );

    final leagues = await service.searchLeagues('premier league');
    final standings = await service.leagueStandings(
      leagueCode: 'PL',
      season: 2026,
    );
    final scorers = await service.topScorers(leagueCode: 'PL', season: 2026);
    final competitionMatches = await service.competitionMatches(
      competitionCode: 'CL',
      season: 2026,
    );
    final teams = await service.competitionTeams('PL');
    final fixtures = await service.teamFixtures(teamId: 40, season: 2026);
    final details = await service.matchDetails(123);

    expect(leagues.single['league']['code'], 'PL');
    expect(standings.single['points'], 90);
    expect(scorers.single['player']['name'], 'Player');
    expect(competitionMatches.single.fixtureId, 321);
    expect(competitionMatches.single.competition, 'UEFA Champions League');
    expect(competitionMatches.single.status, MatchStatus.upcoming);
    expect(teams.single['team']['id'], 40);
    expect(fixtures, isEmpty);
    expect(details['events'], hasLength(1));
    expect(
      requests.map((uri) => uri.path),
      containsAll([
        '/v4/competitions',
        '/v4/competitions/PL/standings',
        '/v4/competitions/PL/scorers',
        '/v4/competitions/CL/matches',
        '/v4/competitions/PL/teams',
        '/v4/teams/40/matches',
        '/v4/matches/123',
      ]),
    );
  });
}
