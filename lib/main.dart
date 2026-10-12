import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Support test ads on common test devices to prevent ad serving freezes
  MobileAds.instance.updateRequestConfiguration(
    RequestConfiguration(
      testDeviceIds: const [
        '96A39D6D32901C7064299B0E208A0AC0',
        '39461AAC53B2EE6F8FC1CD19CC2E0ABE',
      ],
    ),
  );
  MobileAds.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NumBlock 2048',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          surface: Color(0xFF1E293B),
        ),
      ),
      home: const GamePage(),
    );
  }
}

// ============================================================
//  Palette & Styles — Merge Infinity / Dark Neon Theme
// ============================================================
const Color kBgDark = Color(0xFF0B0F19);
const Color kBoardBg = Color(0xFF151D2E);
const Color kEmptyCell = Color(0xFF1E293B);

class GameState {
  final List<List<int>> grid;
  final int score;

  GameState(this.grid, this.score);
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with SingleTickerProviderStateMixin {
  static const int gridSize = 4;

  late List<List<int>> _grid;
  int _score = 0;
  int _highScore = 0;
  bool _gameOver = false;
  bool _won = false;
  bool _keepPlaying = false;

  // Undo system - store only the previous state for single-step undo
  GameState? _previousState;

  // Tile pop animation
  late final AnimationController _popController;
  late final Animation<double> _popAnimation;

  final Random _random = Random();

  // ---------------- AdMob ----------------
  BannerAd? _bannerAd;
  bool _bannerAdIsLoaded = false;
  InterstitialAd? _interstitialAd;
  int _numAttemptsToLoadInterstitial = 0;
  static const int maxFailedLoadAttempts = 3;
  int _bannerRetryCount = 0;

  static const String bannerUnitId = 'ca-app-pub-4200142906990707/7061148582';
  static const String interstitialUnitId = 'ca-app-pub-4200142906990707/6475745098';

  @override
  void initState() {
    super.initState();
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _popAnimation = CurvedAnimation(parent: _popController, curve: Curves.easeOutBack);
    _initGame();
    _initAds();
  }

  // ============================================================
  //  Game state & Undo
  // ============================================================
  void _initGame() {
    setState(() {
      _grid = List.generate(gridSize, (_) => List.filled(gridSize, 0));
      _score = 0;
      _gameOver = false;
      _won = false;
      _keepPlaying = false;
      _previousState = null;
      _addRandomTile();
      _addRandomTile();
    });
    _loadHighScore();
  }

  void _undo() {
    if (_previousState == null) return;
    setState(() {
      _grid = List.generate(gridSize, (r) => List<int>.from(_previousState!.grid[r]));
      _score = _previousState!.score;
      if (_gameOver) {
        _gameOver = false;
      }
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      _previousState = null;
    });
  }

  void _addRandomTile() {
    final List<Point<int>> emptyTiles = [];
    for (int row = 0; row < gridSize; row++) {
      for (int col = 0; col < gridSize; col++) {
        if (_grid[row][col] == 0) {
          emptyTiles.add(Point(row, col));
        }
      }
    }
    if (emptyTiles.isNotEmpty) {
      final Point<int> p = emptyTiles[_random.nextInt(emptyTiles.length)];
      final int value = _random.nextDouble() < 0.9 ? 2 : 4;
      _grid[p.x][p.y] = value;
    }
  }

  Future<void> _loadHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _highScore = prefs.getInt('highScore') ?? 0;
    });
  }

  Future<void> _saveHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    final int currentBest = prefs.getInt('highScore') ?? 0;
    final int newBest = max(currentBest, _score);
    await prefs.setInt('highScore', newBest);
    if (!mounted) return;
    setState(() {
      _highScore = newBest;
    });
  }

  bool _canMove() {
    for (int row = 0; row < gridSize; row++) {
      for (int col = 0; col < gridSize; col++) {
        if (_grid[row][col] == 0) return true;
        if (col < gridSize - 1 && _grid[row][col] == _grid[row][col + 1]) {
          return true;
        }
        if (row < gridSize - 1 && _grid[row][col] == _grid[row + 1][col]) {
          return true;
        }
      }
    }
    return false;
  }

  bool _hasWon() {
    for (final row in _grid) {
      if (row.contains(2048)) return true;
    }
    return false;
  }

  void _afterMove() {
    _addRandomTile();
    _popController.forward(from: 0);
    if (_hasWon() && !_won && !_keepPlaying) {
      _won = true;
      _saveHighScore();
      _showWinDialog();
      return;
    }
    if (!_canMove()) {
      setState(() => _gameOver = true);
      _saveHighScore();
      _showInterstitial();
    }
    setState(() {});
  }

  // ============================================================
  //  Matrix moves
  // ============================================================
  bool _areListsEqual(List<int> a, List<int> b) {
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _compress(List<int> row) {
    final List<int> newRow = [
      for (final v in row)
        if (v != 0) v,
    ];
    while (newRow.length < gridSize) {
      newRow.add(0);
    }
    for (int i = 0; i < gridSize; i++) {
      row[i] = newRow[i];
    }
  }

  void _merge(List<int> row) {
    for (int i = 0; i < gridSize - 1; i++) {
      if (row[i] == row[i + 1] && row[i] != 0) {
        row[i] *= 2;
        _score += row[i];
        row[i + 1] = 0;
      }
    }
  }

  void _transpose() {
    for (int i = 0; i < gridSize; i++) {
      for (int j = i + 1; j < gridSize; j++) {
        final int temp = _grid[i][j];
        _grid[i][j] = _grid[j][i];
        _grid[j][i] = temp;
      }
    }
  }

  // Capture history, perform move, and update state if changed
  void _move(void Function() moveAction) {
    // Capture state BEFORE any transformations (like transpose)
    final oldGrid = List.generate(gridSize, (r) => List<int>.from(_grid[r]));
    final oldScore = _score;

    moveAction();

    bool changed = false;
    for (int i = 0; i < gridSize; i++) {
      if (!_areListsEqual(oldGrid[i], _grid[i])) {
        changed = true;
        break;
      }
    }

    if (changed) {
      _previousState = GameState(oldGrid, oldScore);
      _afterMove();
    } else {
      // If nothing changed, restore the old score (in case _merge modified it)
      _score = oldScore;
    }
  }

  void _doMoveLeft() {
    for (int i = 0; i < gridSize; i++) {
      _compress(_grid[i]);
      _merge(_grid[i]);
      _compress(_grid[i]);
    }
  }

  void _doMoveRight() {
    for (int i = 0; i < gridSize; i++) {
      _grid[i] = _grid[i].reversed.toList();
      _compress(_grid[i]);
      _merge(_grid[i]);
      _compress(_grid[i]);
      _grid[i] = _grid[i].reversed.toList();
    }
  }

  void _moveLeft() => _move(_doMoveLeft);
  void _moveRight() => _move(_doMoveRight);
  void _moveUp() => _move(() {
    _transpose();
    _doMoveLeft();
    _transpose();
  });
  void _moveDown() => _move(() {
    _transpose();
    _doMoveRight();
    _transpose();
  });

  // ============================================================
  //  Ads Handling
  // ============================================================
  void _initAds() {
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _loadBannerAd();
      _loadInterstitialAd();
    });
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: bannerUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _bannerAdIsLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
          _retryBannerAd();
        },
      ),
    )..load();
  }

  void _retryBannerAd() {
    if (_bannerRetryCount >= 5) return;
    _bannerRetryCount++;
    Future<void>.delayed(
      Duration(milliseconds: 2000 * _bannerRetryCount),
      () {
        if (!mounted) return;
        _loadBannerAd();
      },
    );
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
        },
        onAdFailedToLoad: (error) {
          _interstitialAd?.dispose();
          _interstitialAd = null;
          _numAttemptsToLoadInterstitial++;
          if (_numAttemptsToLoadInterstitial < maxFailedLoadAttempts) {
            _loadInterstitialAd();
          }
        },
      ),
    );
  }

  void _showInterstitial() {
    final ad = _interstitialAd;
    if (ad == null) return;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadInterstitialAd();
      },
    );
    ad.show();
    _interstitialAd = null;
  }

  // ============================================================
  //  Dialogs (Modern Glass/Dark Style)
  // ============================================================
  void _showWinDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 30,
                offset: Offset(0, 10),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              const Text(
                'INFINITY REACHED!',
                style: TextStyle(
                  fontFamily: 'Rubik',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Score: $_score',
                style: const TextStyle(
                  fontFamily: 'Rubik',
                  fontSize: 16,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _DialogButton(
                    label: 'Continue',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      setState(() => _keepPlaying = true);
                    },
                  ),
                  const SizedBox(width: 12),
                  _DialogButton(
                    label: 'New Game',
                    filled: true,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _initGame();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGameOverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 30,
                offset: Offset(0, 10),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'NO MOVES LEFT',
                style: TextStyle(
                  fontFamily: 'Rubik',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Color(0xFFF43F5E),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '$_score',
                style: const TextStyle(
                  fontFamily: 'Rubik',
                  fontSize: 44,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Text(
                'TOTAL SCORE',
                style: TextStyle(
                  fontFamily: 'Rubik',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 24),
              _DialogButton(
                label: 'TRY AGAIN',
                filled: true,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _initGame();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  //  Build Functions & Modern Layout
  // ============================================================
  void _handleSwipe(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    final double dx = velocity.dx;
    final double dy = velocity.dy;

    const double threshold = 200.0;
    if (dx.abs() < threshold && dy.abs() < threshold) return;

    if (dx.abs() > dy.abs()) {
      if (dx > 0) {
        _moveRight();
      } else {
        _moveLeft();
      }
    } else {
      if (dy > 0) {
        _moveDown();
      } else {
        _moveUp();
      }
    }

    if (_gameOver) _showGameOverDialog();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgDark,
      body: SafeArea(
        child: GestureDetector(
          onPanEnd: _handleSwipe,
          child: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.4),
                radius: 1.2,
                colors: [Color(0xFF1E293B), Color(0xFF0B0F19)],
              ),
            ),
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildBoard()),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        color: const Color(0xFF0B0F19),
        height: 60,
        alignment: Alignment.center,
        child: _bannerAdIsLoaded && _bannerAd != null
            ? SizedBox(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              )
            : const Text(
                'AdMob Banner',
                style: TextStyle(
                  fontFamily: 'Rubik',
                  fontSize: 12,
                  letterSpacing: 1.0,
                  color: Colors.white24,
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'NUMBLOCK',
                    style: TextStyle(
                      fontFamily: 'Rubik',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.5,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                  Text(
                    '2048',
                    style: TextStyle(
                      fontFamily: 'Rubik',
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.0,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              _ScoreCard(title: 'SCORE', value: _score),
              const SizedBox(width: 8),
              _ScoreCard(title: 'BEST', value: _highScore),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Action Buttons: Undo & Reset
              _IconButton(
                icon: Icons.undo_rounded,
                enabled: _previousState != null,
                onTap: _undo,
              ),
              const SizedBox(width: 8),
              _IconButton(
                icon: Icons.refresh_rounded,
                enabled: true,
                onTap: _initGame,
              ),
              const Spacer(),
              const Text(
                'Join tiles to reach 2048',
                style: TextStyle(
                  fontFamily: 'Rubik',
                  fontSize: 13,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBoard() {
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kBoardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.04), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double cellSize =
                  (constraints.maxWidth - 12 * (gridSize - 1)) / gridSize;
              if (cellSize <= 0) return const SizedBox.expand();

              return Stack(
                children: [
                  // Empty cells background
                  for (int row = 0; row < gridSize; row++)
                    for (int col = 0; col < gridSize; col++)
                      Positioned(
                        left: col * (cellSize + 12),
                        top: row * (cellSize + 12),
                        child: Container(
                          width: cellSize,
                          height: cellSize,
                          decoration: BoxDecoration(
                            color: kEmptyCell,
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                  // Filled tiles
                  for (int row = 0; row < gridSize; row++)
                    for (int col = 0; col < gridSize; col++)
                      if (_grid[row][col] != 0)
                        Positioned(
                          left: col * (cellSize + 12),
                          top: row * (cellSize + 12),
                          child: _Tile(
                            value: _grid[row][col],
                            size: cellSize,
                            pop: _popAnimation,
                          ),
                        ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _popController.dispose();
    super.dispose();
  }
}

// ============================================================
//  Neon Tiles & Component Styling
// ============================================================
class _ScoreCard extends StatelessWidget {
  final String title;
  final int value;

  const _ScoreCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 70),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Rubik',
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$value',
            style: const TextStyle(
              fontFamily: 'Rubik',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _IconButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: enabled ? Colors.white : Colors.white24,
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool filled;

  const _DialogButton({
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? const Color(0xFF38BDF8) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: filled ? null : Border.all(color: Colors.white24),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Rubik',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: filled ? const Color(0xFF0F172A) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final int value;
  final double size;
  final Animation<double> pop;

  const _Tile({
    required this.value,
    required this.size,
    required this.pop,
  });

  @override
  Widget build(BuildContext context) {
    final bool isNew = value == 2 || value == 4;
    final List<Color> colors = _tileColors(value);

    final Widget tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.35),
            blurRadius: value >= 64 ? 14 : 6,
            offset: const Offset(0, 4),
          )
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$value',
        style: TextStyle(
          fontFamily: 'Rubik',
          fontSize: _fontSize(value),
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );

    if (isNew) {
      return ScaleTransition(scale: pop, child: tile);
    }
    return tile;
  }

  List<Color> _tileColors(int value) {
    switch (value) {
      case 2:
        return const [Color(0xFF334155), Color(0xFF1E293B)]; // Soft Slate
      case 4:
        return const [Color(0xFF0284C7), Color(0xFF0369A1)]; // Electric Blue
      case 8:
        return const [Color(0xFF0D9488), Color(0xFF0F766E)]; // Emerald Teal
      case 16:
        return const [Color(0xFF16A34A), Color(0xFF15803D)]; // Neon Green
      case 32:
        return const [Color(0xFFCA8A04), Color(0xFFA16207)]; // Golden Yellow
      case 64:
        return const [Color(0xFFEA580C), Color(0xFFC2410C)]; // Bright Orange
      case 128:
        return const [Color(0xFFE11D48), Color(0xFFBE123C)]; // Neon Crimson
      case 256:
        return const [Color(0xFF9333EA), Color(0xFF7E22CE)]; // Electric Violet
      case 512:
        return const [Color(0xFF4F46E5), Color(0xFF4338CA)]; // Deep Indigo
      case 1024:
        return const [Color(0xFFEC4899), Color(0xFFBE185D)]; // Pink Blast
      case 2048:
        return const [Color(0xFFF59E0B), Color(0xFFD97706)]; // Supernova Sun
      default:
        return const [Color(0xFF8B5CF6), Color(0xFF3B82F6)]; // Cosmic Infinity
    }
  }

  double _fontSize(int value) {
    if (value < 100) return size * 0.40;
    if (value < 1000) return size * 0.32;
    return size * 0.26;
  }
}
