import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/models.dart';
import '../../services/veilborn_service.dart';
import '../../config/theme.dart';
import '../../widgets/card/card_widget.dart';

// =============================================================================
// CollectionScreen — Browse, filter, and inspect owned cards
// =============================================================================

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  final _service = VeilbornService.instance;
  List<OwnedCard> _allCards = [];
  List<OwnedCard> _filtered = [];
  bool _loading = true;

  // Filters
  String? _typeFilter;
  String? _rarityFilter;
  bool _showDormant = true;
  String _sortBy = 'level'; // level, rarity, attack, name

  OwnedCard? _inspecting;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  Future<void> _loadCards() async {
    final cards = await _service.getMyCards();
    if (!mounted) return;
    setState(() {
      _allCards = cards;
      _loading = false;
      _applyFilters();
    });
  }

  void _applyFilters() {
    var result = List<OwnedCard>.from(_allCards);

    if (_typeFilter != null) {
      result = result.where((c) => c.definition.cardType.label == _typeFilter).toList();
    }
    if (_rarityFilter != null) {
      result = result.where((c) => c.definition.rarity.label == _rarityFilter).toList();
    }
    if (!_showDormant) {
      result = result.where((c) => !c.isDormant).toList();
    }

    result.sort((a, b) {
      switch (_sortBy) {
        case 'rarity':
          return b.definition.rarity.sortOrder.compareTo(a.definition.rarity.sortOrder);
        case 'attack':
          return b.attack.compareTo(a.attack);
        case 'name':
          return a.definition.name.compareTo(b.definition.name);
        default: // level
          return b.level.compareTo(a.level);
      }
    });

    setState(() => _filtered = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VeilbornColors.obsidian,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildFilterBar(),
            if (_loading)
              const Expanded(child: Center(
                child: CircularProgressIndicator(color: VeilbornColors.spectreViolet, strokeWidth: 2),
              ))
            else
              Expanded(child: _buildCardGrid()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('COLLECTION', style: VeilbornTextStyles.display(22)),
              Text(
                '${_filtered.length} of ${_allCards.length} cards',
                style: VeilbornTextStyles.body(13, color: VeilbornColors.ashGrey),
              ),
            ],
          ),
          // Sort picker
          _buildSortPicker(),
        ],
      ),
    );
  }

  Widget _buildSortPicker() {
    return DropdownButton<String>(
      value: _sortBy,
      dropdownColor: VeilbornColors.rifted,
      style: VeilbornTextStyles.ui(12),
      underline: const SizedBox.shrink(),
      items: const [
        DropdownMenuItem(value: 'level', child: Text('Level')),
        DropdownMenuItem(value: 'rarity', child: Text('Rarity')),
        DropdownMenuItem(value: 'attack', child: Text('Attack')),
        DropdownMenuItem(value: 'name', child: Text('Name')),
      ],
      onChanged: (v) {
        if (v != null) setState(() { _sortBy = v; _applyFilters(); });
      },
    );
  }

  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          // Type filters
          ...['Specter', 'Revenant', 'Phantom', 'Behemoth'].map((type) =>
            _filterChip(
              label: type,
              isActive: _typeFilter == type,
              color: VeilbornColors.typeColor(type),
              onTap: () => setState(() {
                _typeFilter = _typeFilter == type ? null : type;
                _applyFilters();
              }),
            ),
          ),
          const SizedBox(width: 8),
          // Rarity filters
          ...['Common', 'Rare', 'Epic', 'Legendary'].map((rarity) =>
            _filterChip(
              label: rarity,
              isActive: _rarityFilter == rarity,
              color: VeilbornColors.rarityColor(rarity),
              onTap: () => setState(() {
                _rarityFilter = _rarityFilter == rarity ? null : rarity;
                _applyFilters();
              }),
            ),
          ),
          const SizedBox(width: 8),
          // Dormant toggle
          _filterChip(
            label: '💤 Dormant',
            isActive: !_showDormant,
            color: VeilbornColors.ashGrey,
            onTap: () => setState(() {
              _showDormant = !_showDormant;
              _applyFilters();
            }),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool isActive,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.2) : VeilbornColors.rifted,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? color : VeilbornColors.hollow,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: VeilbornTextStyles.ui(11, color: isActive ? color : VeilbornColors.ashGrey),
        ),
      ),
    );
  }

  Widget _buildCardGrid() {
    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.blur_on, color: VeilbornColors.hollow, size: 48),
            const SizedBox(height: 12),
            Text('No cards found', style: VeilbornTextStyles.body(16, color: VeilbornColors.ashGrey)),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 120 / 180,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _filtered.length,
      itemBuilder: (context, i) {
        final card = _filtered[i];
        return VeilbornCardWidget(
          card: card,
          size: CardSize.compact,
          onTap: () => _showCardDetail(card),
        )
            .animate(delay: Duration(milliseconds: i * 30))
            .fadeIn(duration: 300.ms)
            .scale(begin: const Offset(0.9, 0.9));
      },
    );
  }

  void _showCardDetail(OwnedCard card) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _CardDetailSheet(card: card),
    );
  }
}

// ---------------------------------------------------------------------------
// Card detail bottom sheet
// ---------------------------------------------------------------------------

class _CardDetailSheet extends StatelessWidget {
  final OwnedCard card;
  const _CardDetailSheet({required this.card});

  @override
  Widget build(BuildContext context) {
    final typeColor = VeilbornColors.typeColor(card.definition.cardType.label);
    final rarityColor = VeilbornColors.rarityColor(card.definition.rarity.label);

    return Container(
      decoration: BoxDecoration(
        color: VeilbornColors.abyss,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: rarityColor.withOpacity(0.4), width: 1),
      ),
      padding: const EdgeInsets.all(24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: VeilbornColors.hollow,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Card and info side by side
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VeilbornCardWidget(card: card, size: CardSize.full),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Rarity badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: rarityColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: rarityColor.withOpacity(0.5)),
                        ),
                        child: Text(
                          card.definition.rarity.label.toUpperCase(),
                          style: VeilbornTextStyles.ui(10, color: rarityColor),
                        ),
                      ),
                      const SizedBox(height: 8),

                      Text(card.definition.name, style: VeilbornTextStyles.display(18)),
                      const SizedBox(height: 4),
                      Text(
                        card.definition.cardType.label,
                        style: VeilbornTextStyles.ui(13, color: typeColor),
                      ),
                      const SizedBox(height: 16),

                      // Type advantage info
                      _infoRow('Beats', card.definition.cardType.beats, VeilbornColors.veilGold),
                      _infoRow('Weak to', card.definition.cardType.weakTo, VeilbornColors.veilCrimson),
                      const SizedBox(height: 12),

                      // Stats
                      _statRow('⚔ Attack', card.attack.toString()),
                      _statRow('🛡 Defense', card.maxDefense.toString()),
                      _statRow('⚡ Speed', card.definition.speed.toString()),
                      _statRow('💧 Mana', card.definition.manaCost.toString()),
                      const SizedBox(height: 12),

                      // XP Progress
                      if (card.level < 5) ...[
                        Text('LEVEL ${card.level}', style: VeilbornTextStyles.ui(11, color: VeilbornColors.ashGrey)),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: card.xpProgress,
                            backgroundColor: VeilbornColors.hollow,
                            valueColor: AlwaysStoppedAnimation(rarityColor),
                            minHeight: 5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${card.xp} / ${card.xpToNextLevel} XP',
                          style: VeilbornTextStyles.ui(10, color: VeilbornColors.ashGrey),
                        ),
                      ] else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: VeilbornColors.veilGold.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: VeilbornColors.veilGold.withOpacity(0.4)),
                          ),
                          child: Text('MAX LEVEL', style: VeilbornTextStyles.ui(11, color: VeilbornColors.veilGold)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Ability
            if (card.definition.hasAbility)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: typeColor.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.definition.abilityEffect?.toUpperCase().replaceAll('_', ' ') ?? '',
                      style: VeilbornTextStyles.ui(11, color: typeColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      card.definition.abilityDesc ?? '',
                      style: VeilbornTextStyles.body(14, italic: true),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // Lore
            Text(
              '"${card.definition.lore}"',
              style: VeilbornTextStyles.body(14, color: VeilbornColors.ashGrey, italic: true),
            ),

            // Dormant warning
            if (card.isDormant) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: VeilbornColors.veilCrimson.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: VeilbornColors.veilCrimson.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bedtime, color: VeilbornColors.veilCrimson, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dormant — resting after 3 consecutive defeats. Returns in 24h.',
                        style: VeilbornTextStyles.body(13, color: VeilbornColors.veilCrimson),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text('$label: ', style: VeilbornTextStyles.ui(12, color: VeilbornColors.ashGrey)),
          Text(value, style: VeilbornTextStyles.ui(12, color: valueColor)),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: VeilbornTextStyles.body(13, color: VeilbornColors.ashGrey)),
          Text(value, style: VeilbornTextStyles.stat(14)),
        ],
      ),
    );
  }
}
