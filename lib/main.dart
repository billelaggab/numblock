import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Enable test ads on this device so banners/interstitials actually load
  // while the app is still in development (production keeps real IDs).
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
      title: '2048',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFfaf8ef),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8f7a66)),
      ),
      home: const GamePage(),
    );
  }
}

// ============================================================
//  Palette — classic 2048 visual identity
// ============================================================
const Color kBoardBackground = Color(0xFFbbada0);
const Color kEmptyCell = Color(0xFFcdc1b4);
const Color kTextDark = Color(0xFF776e65);
const Color kTextLight = Color(0xFFF9F6F2);

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage>
    with SingleTickerProviderStateMixin {
  static const int gridSize = 4;

  late List<List<int>> _grid;
  int _score = 0;
  int _highScore = 0;
  bool _gameOver = false;
  bool _won = false;
  bool _keepPlaying = false;

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
  static const String bannerUnitId =
      'ca-app-pub-4200142906990707/6687961106';
  static const String interstitialUnitId =
      'ca-app-pub-4200142906990707/1051571179';

  @override
  void initState() {
    super.initState();
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _popAnimation =
        CurvedAnimation(parent: _popController, curve: Curves.easeOutBack);
    _initGame();
    _initAds();
  }

  // ============================================================
  //  Game state
  // ============================================================
  void _initGame() {
    setState(() {
      _grid = List.generate(gridSize, (_) => List.filled(gridSize, 0));
      _score = 0;
      _gameOver = false;
      _won = false;
      _keepPlaying = false;
      _addRandomTile();
      _addRandomTile();
    });
    _loadHighScore();
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
    await prefs.setInt('highScore', _score);
    if (!mounted) return;
    setState(() {
      _highScore = max(_highScore, _score);
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

  void _moveLeft() {
    bool changed = false;
    for (int i = 0; i < gridSize; i++) {
      final List<int> row = List.from(_grid[i]);
      _compress(row);
      _merge(row);
      _compress(row);
      if (!_areListsEqual(_grid[i], row)) {
        changed = true;
        _grid[i] = row;
      }
    }
    if (changed) _afterMove();
  }

  void _moveRight() {
    bool changed = false;
    for (int i = 0; i < gridSize; i++) {
      final List<int> original = List.from(_grid[i]);
      final List<int> row = original.reversed.toList();
      _compress(row);
      _merge(row);
      _compress(row);
      final List<int> restored = row.reversed.toList();
      if (!_areListsEqual(original, restored)) {
        changed = true;
        _grid[i] = restored;
      }
    }
    if (changed) _afterMove();
  }

  void _moveUp() {
    _transpose();
    _moveLeft();
    _transpose();
  }

  void _moveDown() {
    _transpose();
    _moveRight();
    _transpose();
  }

  // ============================================================
  //  Ads
  // ============================================================
  void _initAds() {
    // Give the SDK a moment to finish initializing before requesting ads.
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
          debugPrint('>>> Banner ad loaded successfully! <<<');
          if (!mounted) return;
          setState(() => _bannerAdIsLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('>>> Banner failed to load: code=${error.code}, message=${error.message}, responseInfo=${error.responseInfo}');
          ad.dispose();
          _bannerAd = null;
          _retryBannerAd();
        },
      ),
    )..load();
  }

  void _retryBannerAd() {
    // Network hiccup at startup is common — retry a few times.
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
          debugPrint('>>> Interstitial ad loaded successfully! <<<');
          _interstitialAd = ad;
        },
        onAdFailedToLoad: (error) {
          debugPrint('>>> Interstitial failed to load: code=${error.code}, message=${error.message}, responseInfo=${error.responseInfo}');
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
  //  Dialogs
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
            color: kBoardBackground,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '🏆',
                style: TextStyle(fontSize: 56),
              ),
              const SizedBox(height: 12),
              const Text(
                'You win!',
                style: TextStyle(
                  fontFamily: 'Rubik',
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: kTextDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Score: $_score',
                style: const TextStyle(
                  fontFamily: 'Rubik',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _DialogButton(
                    label: 'Keep going',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      setState(() => _keepPlaying = true);
                    },
                  ),
                  const SizedBox(width: 12),
                  _DialogButton(
                    label: 'New game',
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
            color: kBoardBackground,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Game Over!',
                style: TextStyle(
                  fontFamily: 'Rubik',
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: kTextDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Score: $_score',
                style: const TextStyle(
                  fontFamily: 'Rubik',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Best: $_highScore',
                style: const TextStyle(
                  fontFamily: 'Rubik',
                  fontSize: 15,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 24),
              _DialogButton(
                label: 'Play again',
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
  //  Build
  // ============================================================
  void _handleSwipe(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    final double dx = velocity.dx;
    final double dy = velocity.dy;

    // Require a minimum flick velocity to count as a swipe
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
      body: SafeArea(
        child: GestureDetector(
          // Use pan callbacks with velocity-based direction; the board
          // container is NOT scrollable so vertical swipes reach us.
          onPanEnd: _handleSwipe,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildBoard()),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        color: kBoardBackground,
        height: 60,
        alignment: Alignment.center,
        child: _bannerAdIsLoaded && _bannerAd != null
            ? SizedBox(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              )
            : const Text(
                'AdMob',
                style: TextStyle(
                  fontFamily: 'Rubik',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFeee4da),
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                '2048',
                style: TextStyle(
                  fontFamily: 'Rubik',
                  fontSize: 44,
                  fontWeight: FontWeight.bold,
                  color: kTextDark,
                ),
              ),
              const Spacer(),
              _ScoreCard(title: 'SCORE', value: _score),
              const SizedBox(width: 8),
              _ScoreCard(title: 'BEST', value: _highScore),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Join the numbers and get to the 2048 tile!',
                  style: TextStyle(
                    fontFamily: 'Rubik',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: kTextDark,
                  ),
                ),
              ),
              Material(
                color: const Color(0xFF8f7a66),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _initGame,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    child: Text(
                      'New game',
                      style: TextStyle(
                        fontFamily: 'Rubik',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: kTextLight,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildBoard() {
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kBoardBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double cellSize =
                  (constraints.maxWidth - 10 * (gridSize - 1)) / gridSize;
              // First frame can arrive with zero width — skip layout until
              // the board has real constraints.
              if (cellSize <= 0) return const SizedBox.expand();
              return Stack(
                children: [
                  // Empty cells background
                  for (int row = 0; row < gridSize; row++)
                    for (int col = 0; col < gridSize; col++)
                      Positioned(
                        left: col * (cellSize + 10),
                        top: row * (cellSize + 10),
                        child: Container(
                          width: cellSize,
                          height: cellSize,
                          decoration: BoxDecoration(
                            color: kEmptyCell,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                  // Filled tiles
                  for (int row = 0; row < gridSize; row++)
                    for (int col = 0; col < gridSize; col++)
                      if (_grid[row][col] != 0)
                        Positioned(
                          left: col * (cellSize + 10),
                          top: row * (cellSize + 10),
                          child: _Tile(
                            value: _grid[row][col],
                            size: cellSize,
                            pop: _popAnimation,
                          ),
                        ),
                  // Game over veil
                  if (_gameOver)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFfaf8ef).withValues(alpha: .7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Game over!',
                                style: TextStyle(
                                  fontFamily: 'Rubik',
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: kTextDark,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _DialogButton(
                                label: 'Try again',
                                filled: true,
                                onTap: _initGame,
                              ),
                            ],
                          ),
                        ),
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
//  Widgets
// ============================================================
class _ScoreCard extends StatelessWidget {
  final String title;
  final int value;

  const _ScoreCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: kBoardBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Rubik',
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFFeee4da),
            ),
          ),
          Text(
            '$value',
            style: const TextStyle(
              fontFamily: 'Rubik',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
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
      color: filled ? const Color(0xFF8f7a66) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: filled
            ? BorderSide.none
            : const BorderSide(color: Color(0xFF8f7a66), width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Rubik',
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: filled ? kTextLight : const Color(0xFF8f7a66),
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
    final Widget tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _tileColor(value),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        '$value',
        style: TextStyle(
          fontFamily: 'Rubik',
          fontSize: _fontSize(value),
          fontWeight: FontWeight.bold,
          color: value <= 4 ? const Color(0xFF776e65) : kTextLight,
        ),
      ),
    );

    if (isNew) {
      return ScaleTransition(scale: pop, child: tile);
    }
    return AnimatedScale(
      scale: 1.0,
      duration: const Duration(milliseconds: 120),
      child: tile,
    );
  }

  Color _tileColor(int value) {
    switch (value) {
      case 2:
        return const Color(0xFFeee4da);
      case 4:
        return const Color(0xFFede0c8);
      case 8:
        return const Color(0xFFf2b179);
      case 16:
        return const Color(0xFFf59563);
      case 32:
        return const Color(0xFFf67c5f);
      case 64:
        return const Color(0xFFf65e3b);
      case 128:
        return const Color(0xFFedcf72);
      case 256:
        return const Color(0xFFedcc61);
      case 512:
        return const Color(0xFFedc850);
      case 1024:
        return const Color(0xFFedc53f);
      case 2048:
        return const Color(0xFFedc22e);
      default:
        return const Color(0xFF3c3a32); // >2048 super tiles
    }
  }

  double _fontSize(int value) {
    if (value < 100) return size * 0.42;
    if (value < 1000) return size * 0.34;
    return size * 0.27;
  }
}
