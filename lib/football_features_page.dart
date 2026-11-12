import 'package:flutter/material.dart';
import 'package:gosport/football_api_service.dart';
import 'package:url_launcher/url_launcher.dart';

const _featureBackground = Color(0xFF0B0F0E);
const _featureSurface = Color(0xFF141A18);
const _featureMuted = Color(0xFF89928D);
const _featureAccent = Color(0xFFB8F36B);

typedef _Json = Map<String, dynamic>;

_Json _asJson(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

String _value(Object? value, [String fallback = '—']) =>
    value is String && value.isNotEmpty ? value : fallback;

int _number(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

class FootballExplorePage extends StatefulWidget {
  const FootballExplorePage({required this.service, super.key});

  final FootballDataService service;

  @override
  State<FootballExplorePage> createState() => _FootballExplorePageState();
}

class _FootballExplorePageState extends State<FootballExplorePage> {
  final _queryController = TextEditingController();
  bool _loading = false;
  String? _error;
  List<_Json> _results = [];

  int get _currentSeasonStartYear {
    final now = DateTime.now();
    return now.month >= 7 ? now.year : now.year - 1;
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.length < 3) {
      setState(() {
        _error = 'Nhập ít nhất 3 ký tự để tìm kiếm.';
        _results = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _results = [];
    });
    try {
      final results = await widget.service.searchLeagues(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } on MatchDataException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _featureBackground,
      appBar: AppBar(
        backgroundColor: _featureBackground,
        title: const Text('Khám phá bóng đá'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ...const [
            (code: 'CL', name: 'UEFA Champions League'),
            (code: 'PL', name: 'Premier League'),
          ].map(
            (competition) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ResultTile(
                icon: Icons.emoji_events_outlined,
                title: competition.name,
                subtitle: 'Trận đấu, bảng xếp hạng và vua phá lưới',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LeagueOverviewPage(
                      service: widget.service,
                      leagueCode: competition.code,
                      leagueName: competition.name,
                      season: _currentSeasonStartYear,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tìm giải đấu',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Chọn giải đấu để xem trận, bảng xếp hạng, vua phá lưới và danh sách đội.',
            style: TextStyle(color: _featureMuted, height: 1.4),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _queryController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Ví dụ: Premier League, La Liga, England',
              filled: true,
              fillColor: _featureSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                onPressed: _loading ? null : _search,
                icon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: _featureAccent),
              ),
            )
          else if (_error != null)
            _FeatureMessage(message: _error!)
          else if (_results.isEmpty)
            const _FeatureMessage(
              message: 'Nhập tên đội bóng hoặc giải đấu để bắt đầu tìm.',
            )
          else
            ..._results.map(_buildResult),
        ],
      ),
    );
  }

  Widget _buildResult(_Json result) {
    final league = _asJson(result['league']);
    final seasons = league['seasons'];
    final seasonRows = seasons is List
        ? seasons.whereType<Map<String, dynamic>>().toList()
        : <_Json>[];
    final currentSeason = seasonRows.where((item) => item['current'] == true);
    final season = currentSeason.isNotEmpty
        ? currentSeason.first
        : seasonRows.isNotEmpty
        ? seasonRows.last
        : null;
    final seasonYear = _number(_asJson(season)['year'], DateTime.now().year);
    final leagueCode = _value(league['code'], '');
    final name = _value(league['name'], 'Giải đấu');
    final country = _value(league['country']);
    return _ResultTile(
      icon: Icons.emoji_events_outlined,
      title: name,
      subtitle: '$country · Mùa $seasonYear',
      onTap: leagueCode.isEmpty
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LeagueOverviewPage(
                  service: widget.service,
                  leagueCode: leagueCode,
                  leagueName: name,
                  season: seasonYear,
                ),
              ),
            ),
    );
  }
}

class LeagueOverviewPage extends StatefulWidget {
  const LeagueOverviewPage({
    required this.service,
    required this.leagueCode,
    required this.leagueName,
    required this.season,
    this.initialTab = 0,
    super.key,
  }) : assert(initialTab >= 0 && initialTab < 4);

  final FootballDataService service;
  final String leagueCode;
  final String leagueName;
  final int season;
  final int initialTab;

  @override
  State<LeagueOverviewPage> createState() => _LeagueOverviewPageState();
}

class _LeagueOverviewPageState extends State<LeagueOverviewPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late Future<List<Match>> _matches;
  late Future<List<_Json>> _standings;
  late Future<List<_Json>> _scorers;
  late Future<List<_Json>> _teams;
  late int _selectedSeason;

  List<int> get _seasonOptions {
    final now = DateTime.now();
    final currentSeason = now.month >= 7 ? now.year : now.year - 1;
    final latestSeason = currentSeason > widget.season
        ? currentSeason
        : widget.season;
    return List.generate(4, (index) => latestSeason - index);
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _selectedSeason = widget.season;
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _load() {
    _matches = widget.service.competitionMatches(
      competitionCode: widget.leagueCode,
      season: _selectedSeason,
    );
    _standings = widget.service.leagueStandings(
      leagueCode: widget.leagueCode,
      season: _selectedSeason,
    );
    _scorers = widget.service.topScorers(
      leagueCode: widget.leagueCode,
      season: _selectedSeason,
    );
    _teams = widget.service.competitionTeams(widget.leagueCode);
  }

  void _onSeasonChanged(int season) {
    if (season == _selectedSeason) return;
    setState(() {
      _selectedSeason = season;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _featureBackground,
      appBar: AppBar(
        backgroundColor: _featureBackground,
        title: Text(widget.leagueName),
        actions: [
          IconButton(
            tooltip: 'Mở trang trên native-stats',
            onPressed: _openNativeStats,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(
            children: [
              const SizedBox(height: 8),
              _SeasonSelector(
                selectedSeason: _selectedSeason,
                seasons: _seasonOptions,
                onChanged: _onSeasonChanged,
              ),
              TabBar(
                controller: _tabs,
                indicatorColor: _featureAccent,
                tabs: const [
                  Tab(text: 'Trận đấu'),
                  Tab(text: 'Bảng xếp hạng'),
                  Tab(text: 'Vua phá lưới'),
                  Tab(text: 'Đội bóng'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _LeagueMatchesView(future: _matches, service: widget.service),
          _StandingsView(future: _standings),
          _ScorersView(future: _scorers),
          _LeagueTeamsView(future: _teams, service: widget.service),
        ],
      ),
    );
  }

  Future<void> _openNativeStats() async {
    final uri = Uri.parse(
      'https://native-stats.org/competition/${Uri.encodeComponent(widget.leagueCode)}/',
    );
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không mở được trang native-stats.')),
        );
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi khi mở trang: $error')));
      }
    }
  }
}

class _SeasonSelector extends StatelessWidget {
  const _SeasonSelector({
    required this.selectedSeason,
    required this.seasons,
    required this.onChanged,
  });

  final int selectedSeason;
  final List<int> seasons;
  final ValueChanged<int> onChanged;

  String _label(int season) {
    final nextSeason = season + 1;
    return '$season/${nextSeason % 100}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Mùa giải',
              style: TextStyle(
                color: _featureAccent,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: seasons.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final season = seasons[index];
                final isSelected = season == selectedSeason;
                return GestureDetector(
                  onTap: () => onChanged(season),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? _featureAccent : _featureSurface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _label(season),
                      style: TextStyle(
                        color: isSelected ? _featureBackground : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LeagueMatchesView extends StatelessWidget {
  const _LeagueMatchesView({required this.future, required this.service});

  final Future<List<Match>> future;
  final FootballDataService service;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Match>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _FeatureMessage(message: _errorText(snapshot.error));
        }
        if (!snapshot.hasData) return const _FeatureLoading();
        if (snapshot.data!.isEmpty) {
          return const _FeatureMessage(
            message: 'Chưa có trận đấu cho giải đấu/mùa này.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final match = snapshot.data![index];
            return _FixtureTile(
              match: match,
              onTap: match.fixtureId == null
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            MatchDetailsPage(service: service, match: match),
                      ),
                    ),
            );
          },
        );
      },
    );
  }
}

class _StandingsView extends StatelessWidget {
  const _StandingsView({required this.future});

  final Future<List<_Json>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_Json>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _FeatureMessage(message: _errorText(snapshot.error));
        }
        if (!snapshot.hasData) {
          return const _FeatureLoading();
        }
        if (snapshot.data!.isEmpty) {
          return const _FeatureMessage(
            message: 'Chưa có bảng xếp hạng cho giải đấu/mùa này.',
          );
        }
        final rows = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StandingsHeader(),
            ...rows.map((row) {
              final team = _asJson(row['team']);
              final all = _asJson(row['all']);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: _featureSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 27,
                      child: Text(
                        '${_number(row['rank'])}',
                        style: const TextStyle(
                          color: _featureMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _value(team['name']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    SizedBox(
                      width: 35,
                      child: Text('${_number(all['played'])}'),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${_number(row['goalsDiff'])}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(
                      width: 35,
                      child: Text(
                        '${_number(row['points'])}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          color: _featureAccent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _StandingsHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(12, 4, 12, 10),
    child: Row(
      children: [
        SizedBox(width: 27),
        Expanded(
          child: Text(
            'ĐỘI BÓNG',
            style: TextStyle(color: _featureMuted, fontSize: 10),
          ),
        ),
        SizedBox(
          width: 35,
          child: Text(
            'TR',
            style: TextStyle(color: _featureMuted, fontSize: 10),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            'HS',
            textAlign: TextAlign.center,
            style: TextStyle(color: _featureMuted, fontSize: 10),
          ),
        ),
        SizedBox(
          width: 35,
          child: Text(
            'Đ',
            textAlign: TextAlign.end,
            style: TextStyle(color: _featureMuted, fontSize: 10),
          ),
        ),
      ],
    ),
  );
}

class _ScorersView extends StatelessWidget {
  const _ScorersView({required this.future});

  final Future<List<_Json>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_Json>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _FeatureMessage(message: _errorText(snapshot.error));
        }
        if (!snapshot.hasData) return const _FeatureLoading();
        if (snapshot.data!.isEmpty) {
          return const _FeatureMessage(
            message: 'Chưa có dữ liệu vua phá lưới cho giải đấu/mùa này.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final row = snapshot.data![index];
            final player = _asJson(row['player']);
            final team = _asJson(
              row['statistics'] is List &&
                      (row['statistics'] as List).isNotEmpty
                  ? (row['statistics'] as List).first
                  : null,
            );
            final teamInfo = _asJson(team['team']);
            final goals = _asJson(team['goals']);
            final games = _asJson(team['games']);
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _featureSurface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF253126),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: _featureAccent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _value(player['name']),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_value(teamInfo['name'])} · ${_number(games['appearences'])} trận · ${_number(goals['assists'])} kiến tạo',
                          style: const TextStyle(
                            color: _featureMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${_number(goals['total'])}',
                    style: const TextStyle(
                      color: _featureAccent,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _LeagueTeamsView extends StatefulWidget {
  const _LeagueTeamsView({required this.future, required this.service});

  final Future<List<_Json>> future;
  final FootballDataService service;

  @override
  State<_LeagueTeamsView> createState() => _LeagueTeamsViewState();
}

class _LeagueTeamsViewState extends State<_LeagueTeamsView> {
  final _filterController = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_Json>>(
      future: widget.future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _FeatureMessage(message: _errorText(snapshot.error));
        }
        if (!snapshot.hasData) return const _FeatureLoading();
        final teams = snapshot.data!.where((entry) {
          final team = _asJson(entry['team']);
          return _value(
            team['name'],
          ).toLowerCase().contains(_filter.toLowerCase());
        }).toList();
        if (teams.isEmpty) {
          return _FeatureMessage(
            message: _filter.isEmpty
                ? 'Giải đấu chưa có danh sách đội.'
                : 'Không tìm thấy đội phù hợp.',
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                controller: _filterController,
                onChanged: (value) => setState(() => _filter = value.trim()),
                decoration: InputDecoration(
                  hintText: 'Lọc đội bóng trong giải',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: _featureSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: teams.map((entry) {
                  final team = _asJson(entry['team']);
                  final teamId = _number(team['id']);
                  final name = _value(team['name'], 'Đội bóng');
                  return _ResultTile(
                    icon: Icons.shield_outlined,
                    title: name,
                    subtitle: _value(team['country']),
                    onTap: teamId == 0
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => TeamFixturesPage(
                                service: widget.service,
                                teamId: teamId,
                                teamName: name,
                              ),
                            ),
                          ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class TeamFixturesPage extends StatefulWidget {
  const TeamFixturesPage({
    required this.service,
    required this.teamId,
    required this.teamName,
    super.key,
  });

  final FootballDataService service;
  final int teamId;
  final String teamName;

  @override
  State<TeamFixturesPage> createState() => _TeamFixturesPageState();
}

class _TeamFixturesPageState extends State<TeamFixturesPage> {
  late Future<List<Match>> _fixtures;
  late final int _season;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _season = now.month >= 7 ? now.year : now.year - 1;
    _fixtures = widget.service.teamFixtures(
      teamId: widget.teamId,
      season: _season,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _featureBackground,
      appBar: AppBar(
        backgroundColor: _featureBackground,
        title: Text('${widget.teamName} · $_season/${_season + 1}'),
      ),
      body: FutureBuilder<List<Match>>(
        future: _fixtures,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _FeatureMessage(message: _errorText(snapshot.error));
          }
          if (!snapshot.hasData) return const _FeatureLoading();
          if (snapshot.data!.isEmpty) {
            return const _FeatureMessage(
              message: 'Không tìm thấy trận đấu cho mùa giải này.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final match = snapshot.data![index];
              return _FixtureTile(
                match: match,
                onTap: match.fixtureId == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MatchDetailsPage(
                            service: widget.service,
                            match: match,
                          ),
                        ),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}

class MatchDetailsPage extends StatefulWidget {
  const MatchDetailsPage({
    required this.service,
    required this.match,
    super.key,
  });

  final FootballDataService service;
  final Match match;

  @override
  State<MatchDetailsPage> createState() => _MatchDetailsPageState();
}

class _MatchDetailsPageState extends State<MatchDetailsPage> {
  late final Future<_Json> _details;

  @override
  void initState() {
    super.initState();
    _details = widget.service.matchDetails(widget.match.fixtureId!);
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    return Scaffold(
      backgroundColor: _featureBackground,
      appBar: AppBar(
        backgroundColor: _featureBackground,
        leading: IconButton(
          tooltip: 'Quay lại',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Chi tiết trận đấu'),
      ),
      body: FutureBuilder<_Json>(
        future: _details,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _FeatureMessage(message: _errorText(snapshot.error));
          }
          if (!snapshot.hasData) return const _FeatureLoading();
          final details = snapshot.data!;
          final events = details['events'] as List<_Json>? ?? [];
          final lineups = details['lineups'] as List<_Json>? ?? [];
          final statistics = details['statistics'] as List<_Json>? ?? [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _featureSurface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    Text(
                      '${match.competition} · ${match.time}',
                      style: const TextStyle(color: _featureMuted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            match.home,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '${match.homeScore ?? '-'} : ${match.awayScore ?? '-'}',
                          style: const TextStyle(
                            color: _featureAccent,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            match.away,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _sectionTitle('Diễn biến'),
              if (events.isEmpty)
                const _FeatureMessage(message: 'Chưa có sự kiện trận đấu.')
              else
                ...events.map(_eventTile),
              const SizedBox(height: 12),
              _sectionTitle('Đội hình'),
              if (lineups.isEmpty)
                const _FeatureMessage(
                  message:
                      'football-data.org không cung cấp đội hình qua API hiện tại.',
                )
              else
                ...lineups.map(_lineupTile),
              const SizedBox(height: 12),
              _sectionTitle('Thống kê'),
              if (statistics.isEmpty)
                const _FeatureMessage(
                  message:
                      'football-data.org không cung cấp thống kê trận qua API hiện tại.',
                )
              else
                ...statistics.map(_statisticsCard),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      title,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    ),
  );

  Widget _eventTile(_Json event) {
    final team = _asJson(event['team']);
    final player = _asJson(event['player']);
    final assist = _asJson(event['assist']);
    final time = _asJson(event['time']);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _featureSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              "${time['elapsed'] ?? ''}’",
              style: const TextStyle(color: _featureAccent),
            ),
          ),
          Expanded(
            child: Text(
              '${_value(event['type'])} · ${_value(event['detail'])}\n${_value(team['name'])}: ${_value(player['name'])}'
              '${assist['name'] is String ? ' (kiến tạo: ${assist['name']})' : ''}',
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineupTile(_Json lineup) {
    final team = _asJson(lineup['team']);
    final coach = _asJson(lineup['coach']);
    final players = lineup['startXI'];
    final names = players is List
        ? players
              .whereType<Map<String, dynamic>>()
              .map((item) => _value(_asJson(item['player'])['name']))
              .join(', ')
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _featureSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_value(team['name'])} · ${_value(lineup['formation'])}',
            style: const TextStyle(
              color: _featureAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'HLV: ${_value(coach['name'])}',
            style: const TextStyle(color: _featureMuted, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Text(names, style: const TextStyle(fontSize: 12, height: 1.5)),
        ],
      ),
    );
  }

  Widget _statisticsCard(_Json statistics) {
    final team = _asJson(statistics['team']);
    final values = statistics['statistics'];
    final rows = values is List
        ? values.whereType<Map<String, dynamic>>().toList()
        : <_Json>[];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _featureSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _value(team['name']),
            style: const TextStyle(
              color: _featureAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text(_value(row['type']))),
                  Text(_value(row['value'])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FixtureTile extends StatelessWidget {
  const _FixtureTile({required this.match, required this.onTap});

  final Match match;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final score = match.homeScore == null
        ? match.time
        : '${match.homeScore} : ${match.awayScore}';
    return ListTile(
      onTap: onTap,
      tileColor: _featureSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text('${match.home}  $score  ${match.away}'),
      subtitle: Text('${match.competition} · ${match.status.name}'),
      trailing: const Icon(Icons.chevron_right_rounded, color: _featureMuted),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: _featureSurface,
    child: ListTile(
      onTap: onTap,
      leading: Icon(icon, color: _featureAccent),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );
}

class _FeatureLoading extends StatelessWidget {
  const _FeatureLoading();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(color: _featureAccent));
}

class _FeatureMessage extends StatelessWidget {
  const _FeatureMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _featureSurface,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      message,
      style: const TextStyle(color: _featureMuted),
      textAlign: TextAlign.center,
    ),
  );
}

String _errorText(Object? error) => error is MatchDataException
    ? error.message
    : 'Không thể tải dữ liệu: $error';
