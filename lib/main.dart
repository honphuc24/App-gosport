import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:gosport/football_api_service.dart';
import 'package:gosport/football_features_page.dart';
import 'package:gosport/google_auth_service.dart';
import 'package:gosport/sample_match_data_source.dart';

const _useSampleData = bool.fromEnvironment('USE_SAMPLE_DATA');
final ValueNotifier<_FirebaseStatus> _firebaseStatus = ValueNotifier(
  const _FirebaseStatus(),
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GoSportApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializeFirebase());
  });
}

Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp();
    _firebaseStatus.value = const _FirebaseStatus(ready: true);
  } on FirebaseException catch (error) {
    _firebaseStatus.value = _FirebaseStatus(error: error.message ?? error.code);
  } on Exception catch (error) {
    _firebaseStatus.value = _FirebaseStatus(
      error: 'Không thể khởi tạo Firebase: ${error.toString()}',
    );
  }
}

class _FirebaseStatus {
  const _FirebaseStatus({this.ready = false, this.error});

  final bool ready;
  final String? error;
}

const _background = Color(0xFF080808);
const _surface = Color(0xFF171717);
const _surfaceLight = Color(0xFF242424);
const _accent = Color(0xFF399DE8);
const _muted = Color(0xFF9A9A9A);
const _weekdayNames = [
  'Thứ 2',
  'Thứ 3',
  'Thứ 4',
  'Thứ 5',
  'Thứ 6',
  'Thứ 7',
  'Chủ nhật',
];

DateTime _vietnamToday() =>
    DateUtils.dateOnly(DateTime.now().toUtc().add(const Duration(hours: 7)));

class GoSportApp extends StatelessWidget {
  const GoSportApp({
    super.key,
    this.dataSource,
    this.showSampleDataLabel = _useSampleData,
  });

  final MatchDataSource? dataSource;
  final bool showSampleDataLabel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_FirebaseStatus>(
      valueListenable: _firebaseStatus,
      builder: (context, firebaseStatus, _) => MaterialApp(
        title: 'GoSport',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _background,
          colorScheme: const ColorScheme.dark(
            primary: _accent,
            surface: _surface,
            onSurface: Colors.white,
          ),
          fontFamily: 'Roboto',
          useMaterial3: true,
        ),
        home: ScoresPage(
          dataSource: dataSource,
          showSampleDataLabel: showSampleDataLabel,
          firebaseReady: firebaseStatus.ready,
          firebaseInitializationError: firebaseStatus.error,
        ),
      ),
    );
  }
}

class ScoresPage extends StatefulWidget {
  const ScoresPage({
    super.key,
    this.dataSource,
    this.showSampleDataLabel = _useSampleData,
    this.firebaseReady = false,
    this.firebaseInitializationError,
  });

  final MatchDataSource? dataSource;
  final bool showSampleDataLabel;
  final bool firebaseReady;
  final String? firebaseInitializationError;

  @override
  State<ScoresPage> createState() => _ScoresPageState();
}

class _ScoresPageState extends State<ScoresPage> {
  static const _leaguePageSize = 12;

  DateTime _selectedDate = _vietnamToday();
  int _selectedFilter = 0;
  int _upcomingHours = 3;
  int _selectedNav = 0;
  int _visibleLeagueCount = _leaguePageSize;
  String? _selectedLeague;
  String _leagueSearchQuery = '';
  final TextEditingController _leagueSearchController = TextEditingController();
  final ScrollController _homeScrollController = ScrollController();
  List<_LeagueOption> _availableLeagues = [];
  bool _isLoadingLeagues = false;
  String? _leagueErrorMessage;
  final Map<String, Match> _favoriteMatches = {};
  final Map<String, DateTime> _favoriteMatchDates = {};
  final List<Match> _matches = [];
  final Map<Match, DateTime> _matchDates = {};
  final List<String> _filters = const [
    'Giải đấu',
    'Trong trận',
    'Sắp diễn ra',
    'Sớm',
  ];
  late final MatchDataSource _dataSource;
  FootballDataService? _ownedService;
  Timer? _refreshTimer;
  bool _isLoading = true;
  bool _customDateSelection = false;
  bool _childPageOpen = false;
  String? _errorMessage;
  DateTime? _lastUpdated;
  int _requestNumber = 0;

  @override
  void initState() {
    super.initState();
    if (widget.dataSource != null) {
      _dataSource = widget.dataSource!;
    } else if (widget.showSampleDataLabel) {
      _dataSource = SampleMatchDataSource();
    } else {
      _ownedService = FootballDataService();
      _dataSource = _ownedService!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadMatches();
      _loadCompetitions();
    });
    if (!widget.showSampleDataLabel) {
      _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (!_childPageOpen &&
            (_selectedFilter == 2 ||
                DateUtils.isSameDay(_selectedDate, _vietnamToday()))) {
          _loadMatches(showLoading: false);
        }
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _ownedService?.close();
    _leagueSearchController.dispose();
    _homeScrollController.dispose();
    super.dispose();
  }

  List<_DateOption> get _dates {
    final today = _vietnamToday();
    return List.generate(5, (index) {
      final date = today.add(Duration(days: index));
      final label = index == 0 ? 'Hôm nay' : _weekdayNames[date.weekday - 1];
      return _DateOption(
        label: label,
        date: '${date.day} TH ${date.month}',
        value: date,
      );
    });
  }

  Future<void> _loadMatches({bool showLoading = true}) async {
    final requestNumber = ++_requestNumber;
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final upcoming = _selectedFilter == 2;
      final firstDate = upcoming ? _vietnamToday() : _selectedDate;
      final dates = upcoming
          ? [firstDate, firstDate.add(const Duration(days: 1))]
          : [firstDate];
      final matchLists = await Future.wait(dates.map(_dataSource.matchesFor));
      final matches = matchLists.expand((matches) => matches).toList();
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() {
        _matches
          ..clear()
          ..addAll(matches);
        _matchDates
          ..clear()
          ..addEntries([
            for (var index = 0; index < matchLists.length; index++)
              for (final match in matchLists[index])
                MapEntry(match, dates[index]),
          ]);
        for (var index = 0; index < matchLists.length; index++) {
          for (final match in matchLists[index]) {
            final key = _matchFavoriteKey(match, dates[index]);
            if (_favoriteMatches.containsKey(key)) {
              _favoriteMatches[key] = match;
              _favoriteMatchDates[key] = dates[index];
            }
          }
        }
        if (_ownedService == null) {
          _availableLeagues = _leagueOptionsFromMatches(matches);
          _visibleLeagueCount = _leaguePageSize;
        }
        _lastUpdated = DateTime.now();
        _errorMessage = null;
        _isLoading = false;
      });
    } on MatchDataException catch (error) {
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    } on Exception catch (error) {
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() {
        _errorMessage = 'Không thể tải dữ liệu trận đấu: $error';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadCompetitions() async {
    final service = _ownedService;
    if (service == null) return;
    setState(() {
      _isLoadingLeagues = true;
      _leagueErrorMessage = null;
    });
    try {
      final rows = await service.searchLeagues('');
      final leagues = rows.map((row) {
        final value = row['league'];
        final league = value is Map<String, dynamic> ? value : const {};
        return _LeagueOption(
          name: league['name'] is String
              ? league['name'] as String
              : 'Giải đấu',
          country: league['country'] is String
              ? league['country'] as String
              : 'Khác',
          code: league['code'] is String ? league['code'] as String : '',
          emblem: league['emblem'] is String
              ? league['emblem'] as String
              : null,
        );
      }).toList()..sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() {
        _availableLeagues = leagues;
        _visibleLeagueCount = _leaguePageSize;
        _isLoadingLeagues = false;
      });
    } on MatchDataException catch (error) {
      if (!mounted) return;
      setState(() {
        _leagueErrorMessage = error.message;
        _isLoadingLeagues = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _leagueErrorMessage = 'Không thể tải danh sách giải đấu: $error';
        _isLoadingLeagues = false;
      });
    }
  }

  List<_LeagueOption> _leagueOptionsFromMatches(List<Match> matches) {
    final options = <String, _LeagueOption>{};
    for (final match in matches) {
      options.putIfAbsent(
        match.competition,
        () => _LeagueOption(
          name: match.competition,
          country: match.competitionArea,
          code: match.competitionCode,
          emblem: match.competitionEmblem,
        ),
      );
    }
    return options.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  String _matchFavoriteKey(Match match, DateTime date) {
    final fixtureId = match.fixtureId;
    if (fixtureId != null) return 'fixture:$fixtureId';
    return [
      date.year,
      date.month,
      date.day,
      match.competition,
      match.home,
      match.away,
      match.time,
    ].join('|');
  }

  List<_LeagueOption> get _filteredLeagues {
    final query = _leagueSearchQuery.trim().toLowerCase();
    final competitionsWithMatches = _visibleMatches
        .map((match) => match.competition)
        .toSet();
    return _availableLeagues
        .where(
          (league) =>
              competitionsWithMatches.contains(league.name) &&
              (query.isEmpty ||
                  league.name.toLowerCase().contains(query) ||
                  league.country.toLowerCase().contains(query) ||
                  league.code.toLowerCase().contains(query)),
        )
        .toList();
  }

  void _selectLeague(String? league) {
    setState(() {
      _selectedLeague = league;
      _selectedFilter = 0;
      _selectedNav = 0;
    });
    if (league != null) _scrollToMatches();
  }

  void _scrollToMatches() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_homeScrollController.hasClients) {
        _homeScrollController.animateTo(
          _homeScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<Match> get _visibleMatches {
    final now = DateTime.now().toUtc();
    final upcomingEnd = now.add(Duration(hours: _upcomingHours));
    return _matches.where((match) {
      if (_selectedLeague != null && match.competition != _selectedLeague) {
        return false;
      }
      return switch (_selectedFilter) {
        0 => true,
        1 => match.status == MatchStatus.live,
        2 => _isUpcomingWithinWindow(match, now, upcomingEnd),
        3 => _customDateSelection || match.status == MatchStatus.finished,
        _ => false,
      };
    }).toList();
  }

  bool _isUpcomingWithinWindow(
    Match match,
    DateTime now,
    DateTime upcomingEnd,
  ) {
    if (match.status != MatchStatus.upcoming) return false;
    final kickoff = _kickoffUtc(match);
    return kickoff != null &&
        !kickoff.isBefore(now) &&
        !kickoff.isAfter(upcomingEnd);
  }

  DateTime? _kickoffUtc(Match match, {DateTime? matchDate}) {
    if (match.kickoffAt != null) return match.kickoffAt!.toUtc();
    final timeParts = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(match.time);
    if (timeParts == null) return null;
    final date = matchDate ?? _matchDates[match] ?? _selectedDate;
    return DateTime.utc(
      date.year,
      date.month,
      date.day,
      int.parse(timeParts.group(1)!) - 7,
      int.parse(timeParts.group(2)!),
    );
  }

  String _matchDateTimeLabel(Match match, {DateTime? matchDate}) {
    final kickoff = _kickoffUtc(match, matchDate: matchDate);
    if (kickoff == null) return 'Ngày thi đấu chưa xác định';
    final vietnamTime = kickoff.add(const Duration(hours: 7));
    return '${vietnamTime.day.toString().padLeft(2, '0')}/'
        '${vietnamTime.month.toString().padLeft(2, '0')}/'
        '${vietnamTime.year} · ${match.time}';
  }

  void _selectDate(DateTime date, {bool custom = false}) {
    setState(() {
      _selectedDate = date;
      _customDateSelection = custom;
      _selectedLeague = null;
      _isLoading = true;
      _errorMessage = null;
    });
    _loadMatches(showLoading: false);
  }

  Future<void> _pickResultsDate() async {
    final today = _vietnamToday();
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(DateTime(2000))
          ? today
          : _selectedDate.isAfter(today.add(const Duration(days: 365)))
          ? today
          : _selectedDate,
      firstDate: DateTime(2000),
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Chọn ngày xem trận',
    );
    if (selectedDate != null) _selectDate(selectedDate, custom: true);
  }

  void _selectNavigation(int index) {
    if (index < 0 || index > 3) return;
    setState(() {
      _selectedNav = index;
      if (index < 2) _selectedFilter = index;
    });
    if (index < 2) _loadMatches(showLoading: false);
    if (index == 0) _scrollHomeToTop();
    if (index == 1) _scrollToMatches();
  }

  void _scrollHomeToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_homeScrollController.hasClients) {
        _homeScrollController.animateTo(
          _homeScrollController.position.minScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _selectedNav == 3
            ? _ProfilePanel(
                firebaseReady: widget.firebaseReady,
                initializationError: widget.firebaseInitializationError,
              )
            : _selectedNav == 2
            ? _buildFavoritesPage()
            : Column(
                children: [
                  _buildHeader(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: _buildFilterSelector(),
                  ),
                  Expanded(
                    child: ListView(
                      key: const ValueKey('home-scroll'),
                      controller: _homeScrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        _buildGreeting(),
                        const SizedBox(height: 24),
                        _buildDateSelector(),
                        const SizedBox(height: 22),
                        if (_errorMessage != null) ...[
                          _buildErrorNotice(),
                          const SizedBox(height: 16),
                        ],
                        _buildLeagueSelector(),
                        if (_selectedLeague != null ||
                            _selectedFilter != 0) ...[
                          const SizedBox(height: 22),
                          _buildMatchesSection(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }

  Widget _buildFavoritesPage() {
    final favorites = _favoriteMatches.entries.toList()
      ..sort((first, second) {
        final firstKickoff = _kickoffUtc(
          first.value,
          matchDate: _favoriteMatchDates[first.key],
        );
        final secondKickoff = _kickoffUtc(
          second.value,
          matchDate: _favoriteMatchDates[second.key],
        );
        if (firstKickoff == null) return secondKickoff == null ? 0 : 1;
        if (secondKickoff == null) return -1;
        return firstKickoff.compareTo(secondKickoff);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              const Icon(Icons.star_rounded, color: _accent, size: 26),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Trận yêu thích',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${favorites.length} trận',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: favorites.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star_outline_rounded,
                          color: _muted,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Chưa có trận yêu thích',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Nhấn biểu tượng ngôi sao ở một trận đấu để lưu vào đây.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  key: const ValueKey('favorites-scroll'),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    for (final entry in favorites)
                      _buildMatchCard(
                        entry.value,
                        matchDate: _favoriteMatchDates[entry.key],
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      color: _accent,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.sports_soccer,
                      color: _accent,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 9),
                  const Text(
                    'GoSport',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  _roundIconButton(
                    icon: Icons.search_rounded,
                    onTap: _openFootballExplore,
                  ),
                  const SizedBox(width: 8),
                  _roundIconButton(
                    icon: Icons.refresh_rounded,
                    onTap: _loadMatches,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, size: 21, color: Colors.white),
      ),
    );
  }

  Widget _buildGreeting() {
    final matchCount = _matches.length;
    final dayLabel = DateUtils.isSameDay(_selectedDate, _vietnamToday())
        ? 'HÔM NAY'
        : _weekdayNames[_selectedDate.weekday - 1].toUpperCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$dayLabel, '
          '${_selectedDate.day} THÁNG ${_selectedDate.month}',
          style: const TextStyle(
            color: _muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: Text(
                'Tỷ số hôm nay',
                style: const TextStyle(
                  fontSize: 28,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF203022),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.circle, color: _accent, size: 7),
                  const SizedBox(width: 6),
                  Text(
                    '$matchCount trận',
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        const Text(
          'Cập nhật diễn biến bóng đá mới nhất',
          style: TextStyle(color: _muted, fontSize: 13),
        ),
        if (widget.showSampleDataLabel) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF3A2E18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'DỮ LIỆU MẪU · KHÔNG PHẢI TỶ SỐ THẬT',
              style: TextStyle(
                color: Color(0xFFFFD27A),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDateSelector() {
    final dates = _dates;
    final showDatePicker = _selectedFilter == 3;
    return SizedBox(
      height: 88,
      child: ListView.separated(
        key: const ValueKey('date-selector'),
        scrollDirection: Axis.horizontal,
        itemCount: dates.length + (showDatePicker ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == dates.length) {
            return InkWell(
              key: const ValueKey('pick-results-date'),
              onTap: _pickResultsDate,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 96,
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _accent.withValues(alpha: 0.6)),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_month_rounded, color: _accent),
                    SizedBox(height: 4),
                    Text(
                      'Chọn ngày',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final date = dates[index];
          final isSelected = DateUtils.isSameDay(date.value, _selectedDate);
          return InkWell(
            onTap: () => _selectDate(date.value),
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 82,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? _accent : _surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    date.label,
                    style: TextStyle(
                      color: isSelected ? _background : _muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    date.date,
                    style: TextStyle(
                      color: isSelected ? _background : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterSelector() {
    return Container(
      height: 58,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: List.generate(_filters.length, (index) {
          final isSelected = index == _selectedFilter;
          return Expanded(
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedFilter = index;
                  _selectedNav = index == 1 ? 1 : 0;
                });
                _loadMatches(showLoading: false);
                if (index != 0) _scrollToMatches();
              },
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? _accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _filters[index],
                  style: TextStyle(
                    color: isSelected ? _background : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildLeagueSelector() {
    final leagues = _filteredLeagues;
    final visibleLeagues = leagues.take(_visibleLeagueCount).toList();
    final groups = <String, List<_LeagueOption>>{};
    for (final league in visibleLeagues) {
      groups.putIfAbsent(league.country, () => []).add(league);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _leagueSearchController,
          onChanged: (value) => setState(() {
            _leagueSearchQuery = value;
            _visibleLeagueCount = _leaguePageSize;
          }),
          decoration: InputDecoration(
            hintText: 'Tìm tên giải đấu',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: _surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none,
            ),
            suffixIcon: _selectedLeague == null
                ? null
                : IconButton(
                    tooltip: 'Bỏ chọn giải',
                    onPressed: () => _selectLeague(null),
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: 22),
        if (_isLoadingLeagues && leagues.isEmpty)
          const SizedBox(
            height: 110,
            child: Center(child: CircularProgressIndicator(color: _accent)),
          )
        else if (leagues.isEmpty)
          SizedBox(
            height: _leagueErrorMessage == null ? 64 : null,
            child: Center(
              child: Text(
                _leagueErrorMessage ??
                    (_leagueSearchQuery.isEmpty
                        ? 'Chưa có giải đấu nào có trận trong mục này.'
                        : 'Không tìm thấy giải đấu phù hợp.'),
                style: const TextStyle(color: _muted),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else ...[
          const Text(
            'Các cuộc thi hiện có',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          ...groups.entries.map(
            (entry) => _buildLeagueGroup(entry.key, entry.value),
          ),
          if (visibleLeagues.length < leagues.length)
            OutlinedButton(
              onPressed: () => setState(() {
                _visibleLeagueCount += _leaguePageSize;
              }),
              child: Text(
                'Hiện thêm ${leagues.length - visibleLeagues.length} giải đấu',
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildLeagueGroup(String country, List<_LeagueOption> leagues) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          title: Row(
            children: [
              const Icon(Icons.public_rounded, color: _accent, size: 19),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  country,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text('${leagues.length}', style: const TextStyle(color: _muted)),
            ],
          ),
          children: leagues.map((league) => _buildLeagueRow(league)).toList(),
        ),
      ),
    );
  }

  Widget _buildLeagueRow(_LeagueOption league) {
    final matchCount = _matches
        .where((match) => match.competition == league.name)
        .length;
    final selected = _selectedLeague == league.name;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _selectLeague(league.name),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    _buildLeagueEmblem(league, size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        league.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: selected ? _accent : Colors.white,
                        ),
                      ),
                    ),
                    Text(
                      '$matchCount',
                      style: const TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      selected ? Icons.check_circle : Icons.chevron_right,
                      color: selected ? _accent : _muted,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_ownedService != null && league.code.isNotEmpty)
            _leagueRankingMenu(league),
        ],
      ),
    );
  }

  PopupMenuButton<int> _leagueRankingMenu(_LeagueOption league) {
    return PopupMenuButton<int>(
      tooltip: 'Bảng xếp hạng và vua phá lưới',
      icon: const Icon(Icons.leaderboard_outlined, color: _accent, size: 20),
      onSelected: (tab) => _openLeagueOverview(league, initialTab: tab),
      itemBuilder: (context) => const [
        PopupMenuItem(value: 1, child: Text('Bảng xếp hạng')),
        PopupMenuItem(value: 2, child: Text('Vua phá lưới')),
      ],
    );
  }

  void _openLeagueOverview(_LeagueOption league, {required int initialTab}) {
    final service = _ownedService;
    if (service == null || league.code.isEmpty) return;
    final now = DateTime.now();
    final season = now.month >= 7 ? now.year : now.year - 1;
    _pushPage(
      LeagueOverviewPage(
        service: service,
        leagueCode: league.code,
        leagueName: league.name,
        season: season,
        initialTab: initialTab,
      ),
    );
  }

  Future<void> _pushPage(Widget page) async {
    _childPageOpen = true;
    try {
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute<void>(builder: (_) => page));
    } finally {
      if (mounted) _childPageOpen = false;
    }
  }

  Widget _buildLeagueEmblem(_LeagueOption league, {required double size}) {
    final emblem = league.emblem;
    if (emblem == null || emblem.isEmpty) {
      return Icon(
        Icons.emoji_events_outlined,
        color: _accent,
        size: size * 0.72,
      );
    }
    return Image.network(
      emblem,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          Icon(Icons.emoji_events_outlined, color: _accent, size: size * 0.72),
    );
  }

  Widget _buildMatchesSection() {
    final matches = _visibleMatches;
    final title =
        _selectedLeague ??
        (_selectedFilter == 0
            ? 'Giải đấu'
            : _selectedFilter == 1
            ? 'Trong trận'
            : _selectedFilter == 2
            ? 'Sắp diễn ra'
            : 'Sớm');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Text(
              '${matches.length} trận',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
        if (_selectedFilter == 2) ...[
          const SizedBox(height: 12),
          _buildUpcomingWindowSelector(),
        ],
        const SizedBox(height: 12),
        if (_isLoading && _matches.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator(color: _accent)),
          )
        else if (_errorMessage != null) ...[
          _buildErrorNotice(),
          if (matches.isNotEmpty) const SizedBox(height: 12),
          ..._buildMatchList(matches),
        ] else if (matches.isEmpty)
          _buildEmptyState()
        else ...[
          if (_isLoading)
            const LinearProgressIndicator(
              minHeight: 2,
              color: _accent,
              backgroundColor: _surfaceLight,
            ),
          if (_lastUpdated != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                widget.showSampleDataLabel
                    ? 'Dữ liệu minh họa cố định'
                    : 'Cập nhật lúc ${_lastUpdated!.hour.toString().padLeft(2, '0')}:'
                          '${_lastUpdated!.minute.toString().padLeft(2, '0')} · tự làm mới mỗi phút',
                style: const TextStyle(color: _muted, fontSize: 10),
              ),
            ),
          ],
          const SizedBox(height: 10),
          ..._buildMatchList(matches),
        ],
      ],
    );
  }

  List<Widget> _buildMatchList(List<Match> matches) {
    if (_selectedFilter != 2) return matches.map(_buildMatchCard).toList();

    final matchesByLeague = <String, List<Match>>{};
    for (final match in matches) {
      matchesByLeague.putIfAbsent(match.competition, () => []).add(match);
    }
    final leagues = matchesByLeague.keys.toList()
      ..sort((first, second) {
        final firstKickoff = _kickoffUtc(matchesByLeague[first]!.first);
        final secondKickoff = _kickoffUtc(matchesByLeague[second]!.first);
        if (firstKickoff == null) return secondKickoff == null ? 0 : 1;
        if (secondKickoff == null) return -1;
        return firstKickoff.compareTo(secondKickoff);
      });

    return leagues.map((leagueName) {
      final leagueMatches = matchesByLeague[leagueName]!;
      final league = _availableLeagues
          .where((option) => option.name == leagueName)
          .firstOrNull;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey('upcoming-league-$leagueName'),
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    leagueName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (league != null &&
                    _ownedService != null &&
                    league.code.isNotEmpty)
                  _leagueRankingMenu(league),
              ],
            ),
            subtitle: Text('${leagueMatches.length} trận'),
            children: leagueMatches.map(_buildMatchCard).toList(),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildUpcomingWindowSelector() {
    const options = [3, 6, 12, 24];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Thời gian sắp tới',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Row(
          children: options.map((hours) {
            final selected = _upcomingHours == hours;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: hours == options.last ? 0 : 8),
                child: ChoiceChip(
                  key: ValueKey('upcoming-window-$hours'),
                  label: Text('$hours giờ'),
                  selected: selected,
                  onSelected: (_) => setState(() => _upcomingHours = hours),
                  labelStyle: TextStyle(
                    color: selected ? _background : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  selectedColor: _accent,
                  backgroundColor: _surface,
                  side: BorderSide.none,
                  showCheckmark: false,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMatchCard(Match match, {DateTime? matchDate}) {
    final date = matchDate ?? _matchDates[match] ?? _selectedDate;
    final favoriteKey = _matchFavoriteKey(match, date);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _MatchCard(
        match: match,
        dateTimeLabel: _matchDateTimeLabel(match, matchDate: date),
        isFavorite: _favoriteMatches.containsKey(favoriteKey),
        onTap: match.fixtureId == null || _ownedService == null
            ? null
            : () => _pushPage(
                MatchDetailsPage(service: _ownedService!, match: match),
              ),
        onFavoriteTap: () => setState(() {
          if (_favoriteMatches.remove(favoriteKey) != null) {
            _favoriteMatchDates.remove(favoriteKey);
          } else {
            _favoriteMatches[favoriteKey] = match;
            _favoriteMatchDates[favoriteKey] = date;
          }
        }),
      ),
    );
  }

  Widget _buildErrorNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF7777).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _loadMatches,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Thử lại'),
            style: TextButton.styleFrom(foregroundColor: _accent),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final message = _selectedFilter == 1
        ? 'Gói Free chưa hỗ trợ tỷ số trực tiếp. Chọn “Giải đấu” để xem lịch và kết quả có độ trễ.'
        : _selectedLeague != null
        ? 'Không có trận đấu của $_selectedLeague trong mục này.'
        : DateUtils.isSameDay(_selectedDate, _vietnamToday())
        ? 'Không có trận đấu trong mục này.'
        : 'Chưa có lịch thi đấu cho ngày này.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(Icons.sports_soccer, color: _muted, size: 28),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    const items = [
      (icon: Icons.sports_soccer_rounded, label: 'Thể thao'),
      (icon: Icons.play_circle_fill_rounded, label: 'Trận'),
      (icon: Icons.star_rounded, label: 'Yêu thích'),
      (icon: Icons.person_rounded, label: 'Tài khoản'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final isSelected = index == _selectedNav;
              return Expanded(
                child: InkWell(
                  onTap: () => _selectNavigation(index),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item.icon,
                        size: 21,
                        color: isSelected ? _accent : _muted,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          color: isSelected ? _accent : _muted,
                          fontSize: 10,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  void _openFootballExplore() {
    if (_ownedService == null) {
      _showMessage(
        'Tra cứu giải đấu và đội bóng cần kết nối football-data.org bằng API key.',
      );
      return;
    }
    _pushPage(FootballExplorePage(service: _ownedService!));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _surfaceLight,
        ),
      );
  }
}

class _LeagueOption {
  const _LeagueOption({
    required this.name,
    required this.country,
    required this.code,
    this.emblem,
  });

  final String name;
  final String country;
  final String code;
  final String? emblem;
}

class _DateOption {
  const _DateOption({
    required this.label,
    required this.date,
    required this.value,
  });

  final String label;
  final String date;
  final DateTime value;
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.dateTimeLabel,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteTap,
  });

  final Match match;
  final String dateTimeLabel;
  final bool isFavorite;
  final VoidCallback? onTap;
  final VoidCallback onFavoriteTap;

  @override
  Widget build(BuildContext context) {
    final isLive = match.status == MatchStatus.live;
    final hasScore = match.homeScore != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 13),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(18),
            border: isLive
                ? Border.all(color: _accent.withValues(alpha: 0.16))
                : null,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    Icons.emoji_events_outlined,
                    size: 14,
                    color: isLive ? _accent : _muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      match.competition,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (isLive)
                    Row(
                      children: [
                        const Icon(
                          Icons.circle,
                          color: Color(0xFFFF5D5D),
                          size: 6,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          match.minute ?? 'LIVE',
                          style: const TextStyle(
                            color: Color(0xFFFF7777),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      match.status == MatchStatus.finished ? 'FT' : match.time,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onFavoriteTap,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(
                        isFavorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 18,
                        color: isFavorite ? _accent : _muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  dateTimeLabel,
                  style: const TextStyle(color: _muted, fontSize: 10),
                ),
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  _TeamBadge(code: match.homeCode, color: match.homeColor),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      match.home,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 49,
                    child: Text(
                      hasScore
                          ? '${match.homeScore}  :  ${match.awayScore}'
                          : match.time,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: hasScore ? Colors.white : _muted,
                        fontSize: hasScore ? 15 : 12,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      match.away,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  _TeamBadge(code: match.awayCode, color: match.awayColor),
                ],
              ),
              if (onTap != null) ...[
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Xem chi tiết ›',
                    style: TextStyle(color: _muted, fontSize: 10),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamBadge extends StatelessWidget {
  const _TeamBadge({required this.code, required this.color});

  final String code;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 31,
      height: 31,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        code.substring(0, 1),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ProfilePanel extends StatefulWidget {
  const _ProfilePanel({required this.firebaseReady, this.initializationError});

  final bool firebaseReady;
  final String? initializationError;

  @override
  State<_ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends State<_ProfilePanel> {
  bool _isSigningIn = false;
  bool _isRegistering = false;
  bool _obscurePassword = true;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() => _isSigningIn = true);
    try {
      await GoogleAuthService.instance.signInWithGoogle();
    } on FirebaseAuthException catch (error) {
      if (mounted) _showMessage(_authErrorMessage(error));
    } on Exception catch (error) {
      if (mounted) {
        _showMessage('Không thể hoàn tất đăng nhập Google: $error');
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _submitEmailAuth() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSigningIn = true);
    try {
      if (_isRegistering) {
        await GoogleAuthService.instance.createUserWithEmailAndPassword(
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        await GoogleAuthService.instance.signInWithEmailAndPassword(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) _showMessage(_authErrorMessage(error));
    } on Exception catch (error) {
      if (mounted) _showMessage('Không thể xác thực tài khoản: $error');
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showMessage('Nhập email để nhận liên kết đặt lại mật khẩu.');
      return;
    }
    final emailError = _validateEmail(email);
    if (emailError != null) {
      _showMessage(emailError);
      return;
    }

    setState(() => _isSigningIn = true);
    try {
      await GoogleAuthService.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        _showMessage('Đã gửi liên kết đặt lại mật khẩu đến email của bạn.');
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        _showMessage(
          error.code == 'user-not-found'
              ? 'Nếu email đã đăng ký, bạn sẽ nhận được liên kết đặt lại mật khẩu.'
              : _authErrorMessage(error),
        );
      }
    } on Exception catch (error) {
      if (mounted) _showMessage('Không thể gửi email đặt lại mật khẩu: $error');
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await GoogleAuthService.instance.signOut();
    } on FirebaseAuthException catch (error) {
      if (mounted) _showMessage(_authErrorMessage(error));
    } on Exception catch (error) {
      if (mounted) _showMessage('Không thể đăng xuất: $error');
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Vui lòng nhập email.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Email không hợp lệ.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Vui lòng nhập mật khẩu.';
    if (value.length < 6) return 'Mật khẩu cần có ít nhất 6 ký tự.';
    return null;
  }

  String _authErrorMessage(FirebaseAuthException error) => switch (error.code) {
    'email-already-in-use' => 'Email này đã được đăng ký.',
    'invalid-email' => 'Email không hợp lệ.',
    'weak-password' => 'Mật khẩu quá yếu. Hãy dùng ít nhất 6 ký tự.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' => 'Email hoặc mật khẩu không chính xác.',
    'account-exists-with-different-credential' =>
      'Email này đã được đăng ký bằng phương thức đăng nhập khác.',
    'network-request-failed' => 'Không có kết nối mạng. Hãy thử lại.',
    'operation-not-allowed' =>
      _isRegistering
          ? 'Đăng nhập Email/Mật khẩu chưa được bật trong Firebase Authentication.'
          : 'Phương thức đăng nhập này chưa được bật trong Firebase Authentication.',
    'too-many-requests' => 'Có quá nhiều yêu cầu. Vui lòng thử lại sau.',
    'user-disabled' => 'Tài khoản này đã bị vô hiệu hóa.',
    'missing-email' => 'Vui lòng nhập email.',
    'missing-google-id-token' =>
      error.message ?? 'Thiếu cấu hình OAuth Google trong Firebase.',
    _ => error.message ?? 'Đăng nhập thất bại (${error.code}).',
  };

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.firebaseReady) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_outline, color: _accent, size: 54),
              const SizedBox(height: 18),
              const Text(
                'Cần cấu hình Firebase',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tạo Firebase project, thêm ứng dụng Android và bật Email/Password hoặc Google trong Authentication để đăng ký hoặc đăng nhập.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 13, height: 1.5),
              ),
              if (widget.initializationError != null) ...[
                const SizedBox(height: 12),
                Text(
                  widget.initializationError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return StreamBuilder<User?>(
      stream: GoogleAuthService.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Không thể kiểm tra trạng thái tài khoản: ${snapshot.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _accent));
        }

        final user = snapshot.data;
        if (user != null) return _buildSignedInView(user);
        return _buildSignInView();
      },
    );
  }

  Widget _buildSignInView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: _surfaceLight,
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Icon(Icons.person_outline, color: _accent, size: 38),
            ),
            const SizedBox(height: 18),
            const Text(
              'Chào mừng đến GoSport',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Đăng nhập hoặc tạo tài khoản GoSport bằng email, hoặc tiếp tục với Google.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 20),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    key: const ValueKey('auth-email'),
                    controller: _emailController,
                    enabled: !_isSigningIn,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    validator: _validateEmail,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      filled: true,
                      fillColor: _surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('auth-password'),
                    controller: _passwordController,
                    enabled: !_isSigningIn,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: [
                      _isRegistering
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    validator: _validatePassword,
                    onFieldSubmitted: (_) => _submitEmailAuth(),
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Hiện mật khẩu'
                            : 'Ẩn mật khẩu',
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                      filled: true,
                      fillColor: _surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!_isRegistering)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isSigningIn ? null : _sendPasswordReset,
                  child: const Text('Quên mật khẩu?'),
                ),
              )
            else
              const SizedBox(height: 8),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSigningIn ? null : _submitEmailAuth,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: _background,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: _isSigningIn
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _background,
                        ),
                      )
                    : Text(
                        _isRegistering ? 'Đăng ký' : 'Đăng nhập',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            TextButton(
              onPressed: _isSigningIn
                  ? null
                  : () => setState(() {
                      _isRegistering = !_isRegistering;
                      _formKey.currentState?.reset();
                    }),
              child: Text(
                _isRegistering
                    ? 'Đã có tài khoản? Đăng nhập'
                    : 'Chưa có tài khoản? Đăng ký',
                textAlign: TextAlign.center,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Divider(color: _surfaceLight)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('HOẶC', style: TextStyle(color: _muted)),
                  ),
                  Expanded(child: Divider(color: _surfaceLight)),
                ],
              ),
            ),
            FilledButton(
              onPressed: _isSigningIn ? null : _signIn,
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: _background,
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 13,
                ),
              ),
              child: _isSigningIn
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _background,
                      ),
                    )
                  : const Text(
                      'Tiếp tục với Google',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignedInView(User user) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 38,
              backgroundColor: _surfaceLight,
              foregroundImage: user.photoURL == null
                  ? null
                  : NetworkImage(user.photoURL!),
              child: user.photoURL == null
                  ? const Icon(Icons.person, color: _accent, size: 38)
                  : null,
            ),
            const SizedBox(height: 18),
            Text(
              user.displayName ?? 'Tài khoản GoSport',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            if (user.email != null) ...[
              const SizedBox(height: 6),
              Text(
                user.email!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Đăng xuất'),
              style: OutlinedButton.styleFrom(foregroundColor: _accent),
            ),
          ],
        ),
      ),
    );
  }
}
