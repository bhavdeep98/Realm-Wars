import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/veilborn_service.dart';
import '../config/theme.dart';
import '../widgets/card/card_widget.dart';
import 'collection/collection_screen.dart';
import 'battle/battle_screen.dart';

// =============================================================================
// Main App
// =============================================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  runApp(const VeilbornApp());
}

class VeilbornApp extends StatelessWidget {
  const VeilbornApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Veilborn',
      theme: VeilbornTheme.dark,
      debugShowCheckedModeBanner: false,
      home: const _AppRoot(),
    );
  }
}

class _AppRoot extends StatelessWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session;
        if (session == null) return const AuthScreen();
        return const MainShell();
      },
    );
  }
}

// =============================================================================
// Main Shell — bottom nav
// =============================================================================

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final _screens = const [
    HomeScreen(),
    CollectionScreen(),
    ShopScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VeilbornColors.obsidian,
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: VeilbornColors.hollow, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          backgroundColor: VeilbornColors.abyss,
          selectedItemColor: VeilbornColors.boneWhite,
          unselectedItemColor: VeilbornColors.ashGrey,
          selectedLabelStyle: const TextStyle(fontFamily: 'Cinzel', fontSize: 10, letterSpacing: 0.5),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Cinzel', fontSize: 10),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'RIFT'),
            BottomNavigationBarItem(icon: Icon(Icons.style_outlined), activeIcon: Icon(Icons.style), label: 'CARDS'),
            BottomNavigationBarItem(icon: Icon(Icons.storefront_outlined), activeIcon: Icon(Icons.storefront), label: 'SHOP'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'VEILWEAVER'),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Home Screen
// =============================================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = VeilbornService.instance;
  PlayerProfile? _profile;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final id = _service.currentUserId;
    if (id == null) return;
    final profile = await _service.getProfile(id);
    if (mounted) setState(() => _profile = profile);
  }

  Future<void> _startMatchmaking() async {
    setState(() => _searching = true);
    try {
      final matchId = await _service.findOrCreateMatch();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BattleScreen(matchId: matchId)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: VeilbornColors.veilCrimson,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VeilbornColors.obsidian,
      body: Stack(
        children: [
          // Background rift effect
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.5),
                  radius: 1.0,
                  colors: [Color(0xFF1A0A2E), Color(0xFF080810)],
                ),
              ),
            ),
          ),
          // Animated rift lines
          ..._buildRiftLines(),

          SafeArea(
            child: Column(
              children: [
                // Top bar
                _buildTopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        _buildHeroSection(),
                        const SizedBox(height: 32),
                        _buildMatchmakingButton(),
                        const SizedBox(height: 24),
                        _buildQuickStats(),
                        const SizedBox(height: 24),
                        _buildRecentActivity(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('VEILBORN', style: VeilbornTextStyles.display(20)),
          // Currency display
          if (_profile != null)
            Row(
              children: [
                _currencyChip('💎 ${_profile!.crystals}', VeilbornColors.phantomIndigo),
                const SizedBox(width: 8),
                _currencyChip('⚗ ${_profile!.shards}', VeilbornColors.veilGold),
              ],
            ),
        ],
      ),
    );
  }

  Widget _currencyChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Text(label, style: VeilbornTextStyles.ui(11, color: color)),
    );
  }

  Widget _buildHeroSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_profile != null) ...[
          Text(
            'Welcome back,',
            style: VeilbornTextStyles.body(16, color: VeilbornColors.ashGrey),
          ),
          Text(
            _profile!.displayName,
            style: VeilbornTextStyles.display(32),
          ),
          const SizedBox(height: 4),
          Text(
            'Veilweaver Level ${_profile!.veilweaverLevel}  •  ${_profile!.eloRating} ELO',
            style: VeilbornTextStyles.body(14, color: VeilbornColors.ashGrey),
          ),
        ] else
          Text('THE RIFT AWAITS', style: VeilbornTextStyles.display(32)),
      ],
    ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildMatchmakingButton() {
    return GestureDetector(
      onTap: _searching ? null : _startMatchmaking,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        height: 80,
        decoration: BoxDecoration(
          gradient: _searching
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF8B0000), Color(0xFFB01020), Color(0xFF8B0000)],
                ),
          color: _searching ? VeilbornColors.rifted : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _searching
                ? VeilbornColors.hollow
                : VeilbornColors.veilCrimson.withOpacity(0.7),
            width: 1,
          ),
          boxShadow: _searching
              ? null
              : [
                  BoxShadow(
                    color: VeilbornColors.veilCrimson.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
        ),
        child: Center(
          child: _searching
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: VeilbornColors.ashGrey,
                        strokeWidth: 2,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'ENTERING THE RIFT...',
                      style: VeilbornTextStyles.ui(15, color: VeilbornColors.ashGrey),
                    ),
                  ],
                )
              : Text(
                  'ENTER THE RIFT',
                  style: VeilbornTextStyles.display(18, color: VeilbornColors.boneWhite),
                ),
        ),
      ),
    ).animate().fadeIn(duration: 600.ms, delay: 200.ms).slideY(begin: 0.3, end: 0);
  }

  Widget _buildQuickStats() {
    if (_profile == null) return const SizedBox.shrink();
    final winRate = (_profile!.winRate * 100).toStringAsFixed(0);
    return Row(
      children: [
        _statCard('${_profile!.matchesPlayed}', 'MATCHES'),
        const SizedBox(width: 10),
        _statCard('$winRate%', 'WIN RATE'),
        const SizedBox(width: 10),
        _statCard('${_profile!.winStreak}', 'STREAK'),
      ],
    ).animate().fadeIn(duration: 600.ms, delay: 400.ms);
  }

  Widget _statCard(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: VeilbornColors.rifted,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: VeilbornColors.hollow),
        ),
        child: Column(
          children: [
            Text(value, style: VeilbornTextStyles.stat(22)),
            const SizedBox(height: 2),
            Text(label, style: VeilbornTextStyles.ui(10, color: VeilbornColors.ashGrey)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('RECENT BATTLES', style: VeilbornTextStyles.ui(12, color: VeilbornColors.ashGrey)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: VeilbornColors.rifted,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: VeilbornColors.hollow),
          ),
          child: Center(
            child: Text(
              'Your battle history will appear here',
              style: VeilbornTextStyles.body(14, color: VeilbornColors.ashGrey),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 600.ms, delay: 600.ms);
  }

  List<Widget> _buildRiftLines() {
    return List.generate(3, (i) => Positioned(
      top: 100.0 + i * 180,
      left: -50,
      right: -50,
      child: Transform.rotate(
        angle: -0.15,
        child: Container(
          height: 1,
          color: VeilbornColors.spectreViolet.withOpacity(0.04 + i * 0.02),
        ),
      )
          .animate(delay: Duration(milliseconds: i * 300), onPlay: (c) => c.repeat())
          .fadeIn(duration: 2000.ms)
          .then()
          .fadeOut(duration: 2000.ms),
    ));
  }
}

// =============================================================================
// Shop Screen
// =============================================================================

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final _service = VeilbornService.instance;
  List<CardPack> _packs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  Future<void> _loadPacks() async {
    final packs = await _service.getAvailablePacks();
    if (mounted) setState(() { _packs = packs; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VeilbornColors.obsidian,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Text('THE DARK MARKET', style: VeilbornTextStyles.display(22)),
            ),
            if (_loading)
              const Expanded(child: Center(
                child: CircularProgressIndicator(color: VeilbornColors.spectreViolet, strokeWidth: 2),
              ))
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('CARD PACKS', style: VeilbornTextStyles.ui(12, color: VeilbornColors.ashGrey)),
                    const SizedBox(height: 12),
                    ..._packs.map((pack) => _PackCard(pack: pack)),
                    const SizedBox(height: 24),
                    Text('CRYSTALS', style: VeilbornTextStyles.ui(12, color: VeilbornColors.ashGrey)),
                    const SizedBox(height: 12),
                    ..._buildCrystalBundles(),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCrystalBundles() {
    final bundles = [
      {'crystals': 100, 'price': '\$0.99', 'bonus': null},
      {'crystals': 500, 'price': '\$3.99', 'bonus': '+50 Bonus'},
      {'crystals': 1200, 'price': '\$7.99', 'bonus': '+200 Bonus'},
      {'crystals': 2500, 'price': '\$14.99', 'bonus': 'Best Value'},
    ];

    return bundles.map((b) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VeilbornColors.rifted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VeilbornColors.hollow),
      ),
      child: Row(
        children: [
          const Icon(Icons.diamond, color: VeilbornColors.phantomIndigo, size: 24),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${b['crystals']} Crystals',
                style: VeilbornTextStyles.display(15),
              ),
              if (b['bonus'] != null)
                Text(b['bonus']!.toString(),
                  style: VeilbornTextStyles.ui(11, color: VeilbornColors.veilGold)),
            ],
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: VeilbornColors.phantomIndigo,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(b['price']!.toString(), style: VeilbornTextStyles.ui(13)),
          ),
        ],
      ),
    )).toList();
  }
}

class _PackCard extends StatelessWidget {
  final CardPack pack;
  const _PackCard({required this.pack});

  @override
  Widget build(BuildContext context) {
    final isCrystal = pack.crystalCost != null;
    final costColor = isCrystal ? VeilbornColors.phantomIndigo : VeilbornColors.veilGold;
    final costLabel = isCrystal ? '💎 ${pack.crystalCost}' : '⚗ ${pack.shardCost}';
    final rarityColor = pack.guaranteedRarity != null
        ? VeilbornColors.rarityColor(pack.guaranteedRarity!)
        : VeilbornColors.ashGrey;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [rarityColor.withOpacity(0.08), VeilbornColors.rifted],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: rarityColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          // Pack icon
          Container(
            width: 56,
            height: 72,
            decoration: BoxDecoration(
              color: rarityColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: rarityColor.withOpacity(0.4)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.style, color: rarityColor, size: 24),
                Text(
                  '×${pack.cardsPerPack}',
                  style: VeilbornTextStyles.ui(10, color: rarityColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pack.name, style: VeilbornTextStyles.display(15)),
                const SizedBox(height: 4),
                Text(pack.description,
                  style: VeilbornTextStyles.body(13, color: VeilbornColors.ashGrey),
                  maxLines: 2),
                if (pack.guaranteedRarity != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Guaranteed: ${pack.guaranteedRarity!}+',
                    style: VeilbornTextStyles.ui(11, color: rarityColor),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: costColor.withOpacity(0.2),
              foregroundColor: costColor,
              side: BorderSide(color: costColor.withOpacity(0.5)),
            ),
            child: Text(costLabel, style: VeilbornTextStyles.ui(12, color: costColor)),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Profile Screen
// =============================================================================

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _service = VeilbornService.instance;
  PlayerProfile? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = _service.currentUserId;
    if (id == null) return;
    final p = await _service.getProfile(id);
    if (mounted) setState(() => _profile = p);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VeilbornColors.obsidian,
      body: SafeArea(
        child: _profile == null
            ? const Center(child: CircularProgressIndicator(color: VeilbornColors.spectreViolet, strokeWidth: 2))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 16),
                    // Avatar placeholder
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: VeilbornColors.rifted,
                        border: Border.all(color: VeilbornColors.hollow, width: 2),
                      ),
                      child: const Icon(Icons.person, color: VeilbornColors.ashGrey, size: 40),
                    ),
                    const SizedBox(height: 12),
                    Text(_profile!.displayName, style: VeilbornTextStyles.display(22)),
                    Text(
                      '@${_profile!.username}',
                      style: VeilbornTextStyles.body(14, color: VeilbornColors.ashGrey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Veilweaver Level ${_profile!.veilweaverLevel}  •  ${_profile!.eloRating} ELO',
                      style: VeilbornTextStyles.ui(12, color: VeilbornColors.ashGrey),
                    ),
                    const SizedBox(height: 24),
                    // Stats grid
                    _statsGrid(),
                    const SizedBox(height: 24),
                    // Sign out
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () async {
                          await _service.signOut();
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: VeilbornColors.hollow),
                        ),
                        child: Text('SIGN OUT', style: VeilbornTextStyles.ui(13, color: VeilbornColors.ashGrey)),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _statsGrid() {
    final stats = [
      ('${_profile!.matchesPlayed}', 'Matches'),
      ('${_profile!.matchesWon}', 'Victories'),
      ('${(_profile!.winRate * 100).toStringAsFixed(0)}%', 'Win Rate'),
      ('${_profile!.winStreak}', 'Streak'),
      ('${_profile!.bestWinStreak}', 'Best Streak'),
      ('${_profile!.eloRating}', 'ELO Rating'),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.2,
      children: stats.map((s) => Container(
        decoration: BoxDecoration(
          color: VeilbornColors.rifted,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: VeilbornColors.hollow),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(s.$1, style: VeilbornTextStyles.stat(20)),
            const SizedBox(height: 2),
            Text(s.$2, style: VeilbornTextStyles.ui(10, color: VeilbornColors.ashGrey)),
          ],
        ),
      )).toList(),
    );
  }
}

// =============================================================================
// Auth Screen
// =============================================================================

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;
  String? _error;

  final _service = VeilbornService.instance;

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (_isSignUp) {
        await _service.signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          username: _usernameCtrl.text.trim(),
          displayName: _usernameCtrl.text.trim(),
        );
      } else {
        await _service.signIn(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VeilbornColors.obsidian,
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.3),
                radius: 1.2,
                colors: [Color(0xFF1A0A2E), Color(0xFF080810)],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('VEILBORN', style: VeilbornTextStyles.display(36))
                        .animate()
                        .fadeIn(duration: 800.ms)
                        .slideY(begin: -0.3, end: 0),
                    const SizedBox(height: 8),
                    Text(
                      'The Rift demands tribute',
                      style: VeilbornTextStyles.body(16, color: VeilbornColors.ashGrey, italic: true),
                    ).animate().fadeIn(duration: 800.ms, delay: 200.ms),
                    const SizedBox(height: 40),

                    // Form
                    if (_isSignUp)
                      TextField(
                        controller: _usernameCtrl,
                        decoration: const InputDecoration(labelText: 'Veilweaver Name'),
                        style: VeilbornTextStyles.body(16),
                      ),
                    if (_isSignUp) const SizedBox(height: 12),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                      style: VeilbornTextStyles.body(16),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                      style: VeilbornTextStyles.body(16),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: VeilbornTextStyles.body(13, color: VeilbornColors.veilCrimson)),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(_isSignUp ? 'ENTER THE VEIL' : 'RETURN TO THE RIFT'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => setState(() => _isSignUp = !_isSignUp),
                      child: Text(
                        _isSignUp ? 'Already a Veilweaver? Sign in' : 'New to the Veil? Create account',
                        style: VeilbornTextStyles.body(14, color: VeilbornColors.ashGrey),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
