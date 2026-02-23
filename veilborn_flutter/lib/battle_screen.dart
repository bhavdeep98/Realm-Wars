import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/models.dart';
import '../../services/veilborn_service.dart';
import '../../config/theme.dart';
import '../../widgets/card/card_widget.dart';
import '../../widgets/battle/battle_board.dart';
import '../../widgets/battle/narration_panel.dart';

// =============================================================================
// BattleScreen — Full match experience
//
// Phases:
//   PLACEMENT — player drags cards to grid (60s timer)
//   WAITING   — waiting for opponent to place
//   REVEAL    — all cards flip simultaneously
//   NARRATION — DM narration slides up, image appears
//   NEXT_ROUND — cleanup, next round begins
//   MATCH_OVER — winner declared
// =============================================================================

enum BattleScreenPhase {
  loading,
  placement,
  waitingForOpponent,
  revealing,
  narrating,
  nextRound,
  matchOver,
}

class BattleScreen extends StatefulWidget {
  final String matchId;

  const BattleScreen({super.key, required this.matchId});

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen>
    with SingleTickerProviderStateMixin {
  final _service = VeilbornService.instance;

  // Match state
  Match? _match;
  PlayerProfile? _myProfile;
  PlayerProfile? _opponentProfile;
  List<OwnedCard> _myHand = [];
  int _myMana = 3;
  int _currentRound = 1;

  // Board state
  final Map<String, BoardPlacement> _placements = {};
  OwnedCard? _selectedCard;
  Set<String> _selectedCells = {};

  // Phase
  BattleScreenPhase _phase = BattleScreenPhase.loading;

  // Results
  RoundResult? _lastRoundResult;
  String? _matchWinnerId;

  // Timer
  int _timerSeconds = 60;
  late AnimationController _timerController;

  // Realtime
  dynamic _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _timerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    );
    _initMatch();
  }

  @override
  void dispose() {
    _timerController.dispose();
    if (_realtimeChannel != null) {
      _service.unsubscribeFromMatch(_realtimeChannel);
    }
    super.dispose();
  }

  Future<void> _initMatch() async {
    final match = await _service.getMatch(widget.matchId);
    final profile = await _service.getProfile(_service.currentUserId!);
    final cards = await _service.getMyCards();

    if (!mounted) return;
    setState(() {
      _match = match;
      _myProfile = profile;
      _myHand = cards.take(5).toList();
      _myMana = 3 + match!.currentRound;
      _currentRound = match.currentRound;
      _phase = BattleScreenPhase.placement;
    });

    _subscribeToRealtime();
    _startPlacementTimer();
  }

  void _subscribeToRealtime() {
    _realtimeChannel = _service.subscribeToMatch(
      widget.matchId,
      onRoundResolved: _handleRoundResolved,
      onMatchStateChanged: _handleMatchStateChanged,
    );
  }

  void _handleRoundResolved(Map<String, dynamic> payload) {
    if (!mounted) return;
    final result = RoundResult.fromJson(payload);
    setState(() {
      _lastRoundResult = result;
      _phase = BattleScreenPhase.revealing;
    });

    // Show reveal then narration
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _phase = BattleScreenPhase.narrating);
    });
  }

  void _handleMatchStateChanged(Map<String, dynamic> data) {
    if (!mounted) return;
    if (data['winner_id'] != null) {
      setState(() {
        _matchWinnerId = data['winner_id'] as String;
        _phase = BattleScreenPhase.matchOver;
      });
    }
  }

  void _startPlacementTimer() {
    _timerSeconds = 60;
    _timerController.reset();
    _timerController.forward();

    Future.delayed(const Duration(seconds: 60), () {
      if (mounted && _phase == BattleScreenPhase.placement) {
        _submitPlacements();
      }
    });
  }

  void _selectCard(OwnedCard card) {
    if (_phase != BattleScreenPhase.placement) return;
    if (card.isDormant) return;
    if (card.definition.manaCost > _myMana) return;
    setState(() => _selectedCard = _selectedCard == card ? null : card);
  }

  void _placeCard(int col, RowPosition row) {
    if (_selectedCard == null) return;
    final cellKey = '${col}_${row.name}';
    if (_selectedCells.contains(cellKey)) return;

    setState(() {
      _placements['${col}_${row.name}_${_service.currentUserId}'] = BoardPlacement(
        card: _selectedCard!,
        col: col,
        row: row,
        playerId: _service.currentUserId!,
        currentHp: _selectedCard!.maxDefense,
        faceDown: true,
      );
      _selectedCells.add(cellKey);
      _myMana -= _selectedCard!.definition.manaCost;
      _myHand.remove(_selectedCard);
      _selectedCard = null;
    });
  }

  Future<void> _submitPlacements() async {
    if (_phase != BattleScreenPhase.placement) return;
    setState(() => _phase = BattleScreenPhase.waitingForOpponent);

    // Submit each placement to DB
    for (final entry in _placements.entries) {
      if (!entry.key.contains(_service.currentUserId!)) continue;
      final placement = entry.value;
      await _service.submitPlacement(
        matchId: widget.matchId,
        roundNumber: _currentRound,
        playerCardId: placement.card.instanceId,
        col: placement.col,
        row: placement.row.name,
        manaSpent: placement.card.definition.manaCost,
      );
    }

    // If I'm player1, trigger resolution (server decides when both are ready)
    if (_match?.player1Id == _service.currentUserId) {
      await _service.resolveRound(
        matchId: widget.matchId,
        roundNumber: _currentRound,
      );
    }
  }

  void _onNarrationDismissed() {
    if (_matchWinnerId != null) {
      setState(() => _phase = BattleScreenPhase.matchOver);
      return;
    }

    setState(() {
      _phase = BattleScreenPhase.nextRound;
      _currentRound++;
      _myMana = (3 + _currentRound).clamp(0, 8);
      _placements.clear();
      _selectedCells.clear();
      _selectedCard = null;
      _lastRoundResult = null;
    });

    // Brief pause then start next round
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() => _phase = BattleScreenPhase.placement);
        _startPlacementTimer();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VeilbornColors.obsidian,
      body: Stack(
        children: [
          // Ambient background
          _buildBackground(),

          // Main battle UI
          SafeArea(
            child: Column(
              children: [
                // Top bar: scores, round, timer
                _buildTopBar(),

                // Battle board
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: BattleBoardWidget(
                      myPlayerId: _service.currentUserId ?? '',
                      placements: _placements,
                      selectedCells: _selectedCells,
                      isPlacementPhase: _phase == BattleScreenPhase.placement,
                      isRevealed: _phase == BattleScreenPhase.revealing ||
                          _phase == BattleScreenPhase.narrating,
                      draggingCard: _selectedCard,
                      onCellTap: _placeCard,
                    ),
                  ),
                ),

                // Mana bar
                _buildManaBar(),

                // Hand
                Expanded(
                  flex: 2,
                  child: _buildHand(),
                ),

                // Submit button
                if (_phase == BattleScreenPhase.placement &&
                    _placements.isNotEmpty)
                  _buildSubmitButton(),
              ],
            ),
          ),

          // Phase overlays
          if (_phase == BattleScreenPhase.loading) _buildLoadingOverlay(),
          if (_phase == BattleScreenPhase.waitingForOpponent) _buildWaitingOverlay(),
          if (_phase == BattleScreenPhase.revealing) _buildRevealOverlay(),
          if (_phase == BattleScreenPhase.nextRound) _buildNextRoundOverlay(),
          if (_phase == BattleScreenPhase.matchOver) _buildMatchOverOverlay(),

          // Narration panel (slides up)
          if (_phase == BattleScreenPhase.narrating && _lastRoundResult != null)
            _buildNarrationOverlay(),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.3),
          radius: 1.5,
          colors: [Color(0xFF1A0A2E), Color(0xFF080810)],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          // Opponent score
          _buildScoreChip(
            _opponentProfile?.displayName ?? 'Opponent',
            _match?.player2Score ?? 0,
            isEnemy: true,
          ),

          Expanded(
            child: Column(
              children: [
                // Round indicator
                Text(
                  'ROUND $_currentRound / 5',
                  style: VeilbornTextStyles.ui(11, color: VeilbornColors.ashGrey),
                ),
                const SizedBox(height: 2),
                // Timer bar
                if (_phase == BattleScreenPhase.placement)
                  AnimatedBuilder(
                    animation: _timerController,
                    builder: (context, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: 1 - _timerController.value,
                        backgroundColor: VeilbornColors.hollow,
                        valueColor: AlwaysStoppedAnimation(
                          _timerController.value > 0.75
                              ? VeilbornColors.veilCrimson
                              : VeilbornColors.veilGold,
                        ),
                        minHeight: 4,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // My score
          _buildScoreChip(
            _myProfile?.displayName ?? 'You',
            _match?.player1Score ?? 0,
            isEnemy: false,
          ),
        ],
      ),
    );
  }

  Widget _buildScoreChip(String name, int score, {required bool isEnemy}) {
    return Column(
      children: [
        Text(
          name,
          style: VeilbornTextStyles.ui(10, color: VeilbornColors.ashGrey),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < score
                    ? (isEnemy ? VeilbornColors.veilCrimson : VeilbornColors.veilGold)
                    : VeilbornColors.hollow,
              ),
            ),
          )),
        ),
      ],
    );
  }

  Widget _buildManaBar() {
    const maxMana = 8;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.water_drop, size: 14, color: VeilbornColors.spectreViolet),
          const SizedBox(width: 6),
          Text(
            '$_myMana / $maxMana',
            style: VeilbornTextStyles.ui(11, color: VeilbornColors.spectreViolet),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: List.generate(maxMana, (i) => Expanded(
                child: Container(
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: i < _myMana
                        ? VeilbornColors.spectreViolet
                        : VeilbornColors.hollow,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHand() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _phase == BattleScreenPhase.placement
                ? 'YOUR HAND — Tap to select, then tap a cell'
                : 'HAND',
            style: VeilbornTextStyles.ui(10, color: VeilbornColors.ashGrey),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _myHand.length,
              itemBuilder: (context, i) {
                final card = _myHand[i];
                final isSelected = _selectedCard == card;
                final canAfford = card.definition.manaCost <= _myMana;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Opacity(
                    opacity: (card.isDormant || !canAfford) ? 0.4 : 1.0,
                    child: Transform.translate(
                      offset: isSelected ? const Offset(0, -12) : Offset.zero,
                      child: VeilbornCardWidget(
                        card: card,
                        size: CardSize.compact,
                        isSelected: isSelected,
                        onTap: () => _selectCard(card),
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

  Widget _buildSubmitButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _submitPlacements,
          style: ElevatedButton.styleFrom(
            backgroundColor: VeilbornColors.veilCrimson,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(
            'SEAL PLACEMENTS (${_placements.length} card${_placements.length != 1 ? 's' : ''})',
            style: VeilbornTextStyles.ui(13),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.5, end: 0);
  }

  // Phase overlays

  Widget _buildLoadingOverlay() {
    return Container(
      color: VeilbornColors.obsidian,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: VeilbornColors.spectreViolet, strokeWidth: 2),
            const SizedBox(height: 16),
            Text('ENTERING THE RIFT...', style: VeilbornTextStyles.ui(14)),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        color: VeilbornColors.abyss.withOpacity(0.9),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                color: VeilbornColors.ashGrey,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Awaiting your opponent...',
              style: VeilbornTextStyles.body(14, color: VeilbornColors.ashGrey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevealOverlay() {
    return IgnorePointer(
      child: Center(
        child: Text(
          'REVEALED',
          style: VeilbornTextStyles.display(36, color: VeilbornColors.veilCrimson),
        )
            .animate()
            .fadeIn(duration: 300.ms)
            .scale(begin: const Offset(0.5, 0.5))
            .then(delay: 800.ms)
            .fadeOut(duration: 400.ms),
      ),
    );
  }

  Widget _buildNarrationOverlay() {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => NarrationPanel(
        result: _lastRoundResult!,
        onDismiss: _onNarrationDismissed,
      ),
    ).animate().slideY(begin: 1.0, end: 0, duration: 500.ms, curve: Curves.easeOutCubic);
  }

  Widget _buildNextRoundOverlay() {
    return IgnorePointer(
      child: Center(
        child: Text(
          'ROUND $_currentRound',
          style: VeilbornTextStyles.display(42),
        )
            .animate()
            .fadeIn(duration: 400.ms)
            .scale(begin: const Offset(0.6, 0.6))
            .then(delay: 600.ms)
            .fadeOut(duration: 400.ms),
      ),
    );
  }

  Widget _buildMatchOverOverlay() {
    final iWon = _matchWinnerId == _service.currentUserId;
    return Container(
      color: VeilbornColors.obsidian.withOpacity(0.95),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              iWon ? 'VICTORY' : 'DEFEAT',
              style: VeilbornTextStyles.display(
                48,
                color: iWon ? VeilbornColors.veilGold : VeilbornColors.veilCrimson,
              ),
            ).animate().fadeIn(duration: 600.ms).scale(begin: const Offset(0.5, 0.5)),
            const SizedBox(height: 8),
            Text(
              iWon
                  ? 'The Veil bows to your power'
                  : 'The Veil has swallowed you whole',
              style: VeilbornTextStyles.body(16, italic: true, color: VeilbornColors.ashGrey),
            ).animate().fadeIn(duration: 800.ms, delay: 400.ms),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VeilbornColors.rifted,
                  ),
                  child: const Text('HOME'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacementNamed('/matchmaking');
                  },
                  child: const Text('REMATCH'),
                ),
              ],
            ).animate().fadeIn(duration: 600.ms, delay: 800.ms),
          ],
        ),
      ),
    );
  }
}
