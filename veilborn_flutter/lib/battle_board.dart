import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/models.dart';
import '../../config/theme.dart';
import '../card/card_widget.dart';

// =============================================================================
// BattleBoard — The 4×4 Rift grid
// P2 rows at top, P1 rows at bottom, Veil Line in center.
// Handles placement targeting, reveal animation, and combat flashes.
// =============================================================================

class BattleBoardWidget extends StatelessWidget {
  final String myPlayerId;
  final Map<String, BoardPlacement> placements;   // key: "col_row_playerId"
  final Set<String> selectedCells;                // cells I've targeted
  final bool isPlacementPhase;
  final bool isRevealed;
  final OwnedCard? draggingCard;
  final void Function(int col, RowPosition row)? onCellTap;

  const BattleBoardWidget({
    super.key,
    required this.myPlayerId,
    required this.placements,
    this.selectedCells = const {},
    this.isPlacementPhase = false,
    this.isRevealed = false,
    this.draggingCard,
    this.onCellTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const RadialGradient(
          center: Alignment.center,
          radius: 1.5,
          colors: [Color(0xFF1A1A2E), Color(0xFF080810)],
        ),
        border: Border.all(color: VeilbornColors.hollow, width: 1),
      ),
      child: Column(
        children: [
          // P2 back row
          _buildRow(RowPosition.back, isMyRow: false),
          // P2 front row
          _buildRow(RowPosition.front, isMyRow: false),
          // Veil Line
          _buildVeilLine(),
          // P1 front row
          _buildRow(RowPosition.front, isMyRow: true),
          // P1 back row
          _buildRow(RowPosition.back, isMyRow: true),
        ],
      ),
    );
  }

  Widget _buildVeilLine() {
    return SizedBox(
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pulsing rift line
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  VeilbornColors.spectreViolet.withOpacity(0.6),
                  VeilbornColors.veilCrimson.withOpacity(0.4),
                  VeilbornColors.spectreViolet.withOpacity(0.6),
                  Colors.transparent,
                ],
              ),
            ),
          )
              .animate(onPlay: (c) => c.repeat())
              .fadeIn(duration: 1500.ms)
              .then()
              .fadeOut(duration: 1500.ms),
          // Label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: VeilbornColors.obsidian,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: VeilbornColors.spectreViolet.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Text(
              'THE VEIL',
              style: VeilbornTextStyles.ui(9, color: VeilbornColors.ashGrey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(RowPosition rowPos, {required bool isMyRow}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: List.generate(4, (col) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: _buildCell(col, rowPos, isMyRow: isMyRow),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCell(int col, RowPosition rowPos, {required bool isMyRow}) {
    final cellKey = '${col}_${rowPos.name}_$myPlayerId';
    final oppKey = '${col}_${rowPos.name}_opponent';

    // Get placement for this cell
    BoardPlacement? placement;
    if (isMyRow) {
      placement = placements[cellKey];
    } else {
      placement = placements[oppKey];
    }

    final isSelected = selectedCells.contains('${col}_${rowPos.name}');
    final canTarget = isPlacementPhase && isMyRow && placement == null;
    final hasCard = placement != null;

    return GestureDetector(
      onTap: canTarget ? () => onCellTap?.call(col, rowPos) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 88,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: _cellColor(isMyRow, isSelected, canTarget, hasCard),
          border: Border.all(
            color: _cellBorderColor(isMyRow, isSelected, canTarget, hasCard),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: VeilbornColors.veilGold.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: hasCard
            ? _buildCardInCell(placement!, isMyRow)
            : _buildEmptyCell(col, rowPos, isMyRow, canTarget),
      ),
    );
  }

  Widget _buildCardInCell(BoardPlacement placement, bool isMyRow) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The card
        Padding(
          padding: const EdgeInsets.all(4),
          child: VeilbornCardWidget(
            card: placement.card,
            size: CardSize.mini,
            faceDown: placement.faceDown && !isMyRow,
          ),
        ),

        // HP bar at bottom
        if (!placement.faceDown)
          Positioned(
            bottom: 4,
            left: 4,
            right: 4,
            child: _buildHpBar(placement),
          ),

        // Combat flash overlay (animated)
        if (!placement.faceDown && placement.currentHp <= 0)
          Container(
            decoration: BoxDecoration(
              color: VeilbornColors.veilCrimson.withOpacity(0.6),
              borderRadius: BorderRadius.circular(8),
            ),
          ).animate().fadeIn(duration: 200.ms).then().fadeOut(duration: 400.ms),
      ],
    );
  }

  Widget _buildHpBar(BoardPlacement placement) {
    final maxHp = placement.card.maxDefense;
    final currentHp = placement.currentHp.clamp(0, maxHp);
    final fraction = currentHp / maxHp;

    Color barColor;
    if (fraction > 0.6) {
      barColor = const Color(0xFF2ECC71);
    } else if (fraction > 0.3) {
      barColor = VeilbornColors.veilGold;
    } else {
      barColor = VeilbornColors.veilCrimson;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$currentHp/$maxHp',
          style: VeilbornTextStyles.ui(7, color: VeilbornColors.ghostSilver),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: fraction,
            backgroundColor: VeilbornColors.hollow,
            valueColor: AlwaysStoppedAnimation(barColor),
            minHeight: 3,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyCell(int col, RowPosition rowPos, bool isMyRow, bool canTarget) {
    if (!isMyRow) {
      return const SizedBox.shrink();
    }

    return Center(
      child: canTarget && draggingCard != null
          ? Icon(
              Icons.add_circle_outline,
              color: VeilbornColors.veilGold.withOpacity(0.7),
              size: 20,
            ).animate(onPlay: (c) => c.repeat()).fadeIn(duration: 600.ms).then().fadeOut(duration: 600.ms)
          : Text(
              rowPos == RowPosition.front ? 'FRONT' : 'BACK',
              style: VeilbornTextStyles.ui(8, color: VeilbornColors.hollow),
            ),
    );
  }

  Color _cellColor(bool isMyRow, bool isSelected, bool canTarget, bool hasCard) {
    if (isSelected) return VeilbornColors.veilGold.withOpacity(0.1);
    if (canTarget && draggingCard != null) return VeilbornColors.veilGold.withOpacity(0.05);
    if (!isMyRow) return VeilbornColors.abyss.withOpacity(0.4);
    if (hasCard) return VeilbornColors.rifted.withOpacity(0.6);
    return VeilbornColors.voidDark.withOpacity(0.5);
  }

  Color _cellBorderColor(bool isMyRow, bool isSelected, bool canTarget, bool hasCard) {
    if (isSelected) return VeilbornColors.veilGold;
    if (canTarget && draggingCard != null) return VeilbornColors.veilGold.withOpacity(0.4);
    if (hasCard) return VeilbornColors.hollow;
    return VeilbornColors.hollow.withOpacity(0.4);
  }
}
