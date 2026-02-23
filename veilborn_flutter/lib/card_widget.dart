import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/models.dart';
import '../../config/theme.dart';

// =============================================================================
// VeilbornCard — The visual card component
// Used in collection, deck building, battle board, and pack opening.
// Sizes: full (collection), compact (deck), mini (board), tiny (hand)
// =============================================================================

enum CardSize { full, compact, mini, tiny }

class VeilbornCardWidget extends StatelessWidget {
  final OwnedCard card;
  final CardSize size;
  final bool isSelected;
  final bool isDragging;
  final bool faceDown;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const VeilbornCardWidget({
    super.key,
    required this.card,
    this.size = CardSize.compact,
    this.isSelected = false,
    this.isDragging = false,
    this.faceDown = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final dims = _dimensions(size);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: dims.width,
        height: dims.height,
        transform: isDragging
            ? (Matrix4.identity()..scale(1.08)..translate(0.0, -8.0))
            : Matrix4.identity(),
        child: faceDown ? _buildFaceDown(dims) : _buildFacingUp(dims),
      ),
    );
  }

  Widget _buildFaceDown(_CardDims dims) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(dims.radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A2E), Color(0xFF0D0D1A)],
        ),
        border: Border.all(color: VeilbornColors.hollow, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: VeilbornColors.spectreViolet.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.blur_on,
          color: VeilbornColors.spectreViolet.withOpacity(0.5),
          size: dims.height * 0.3,
        ),
      ),
    );
  }

  Widget _buildFacingUp(_CardDims dims) {
    final typeColor = VeilbornColors.typeColor(card.definition.cardType.label);
    final rarityColor = VeilbornColors.rarityColor(card.definition.rarity.label);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(dims.radius),
        gradient: _cardGradient(card.definition.rarity),
        border: Border.all(
          color: isSelected
              ? VeilbornColors.veilGold
              : rarityColor.withOpacity(0.6),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (isSelected ? VeilbornColors.veilGold : typeColor)
                .withOpacity(isSelected ? 0.4 : 0.15),
            blurRadius: isSelected ? 16 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(dims.radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Art area
            Expanded(
              flex: size == CardSize.full ? 5 : 4,
              child: _buildArtArea(typeColor, rarityColor, dims),
            ),

            // Info area
            Padding(
              padding: EdgeInsets.all(dims.padding),
              child: _buildInfoArea(typeColor, rarityColor, dims),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtArea(Color typeColor, Color rarityColor, _CardDims dims) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Art image or placeholder
        if (card.definition.artUrl.isNotEmpty)
          CachedNetworkImage(
            imageUrl: card.definition.artUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => _artPlaceholder(typeColor),
            errorWidget: (context, url, error) => _artPlaceholder(typeColor),
          )
        else
          _artPlaceholder(typeColor),

        // Gradient overlay at bottom for text legibility
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: dims.height * 0.25,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  VeilbornColors.abyss.withOpacity(0.9),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Type badge
        Positioned(
          top: dims.padding,
          right: dims.padding,
          child: _typeBadge(typeColor, dims),
        ),

        // Level badge
        if (card.level > 1)
          Positioned(
            top: dims.padding,
            left: dims.padding,
            child: _levelBadge(dims),
          ),

        // Rarity glow at bottom of art
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 2,
          child: Container(color: rarityColor.withOpacity(0.8)),
        ),
      ],
    );
  }

  Widget _buildInfoArea(Color typeColor, Color rarityColor, _CardDims dims) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Card name
        Text(
          card.definition.name,
          style: VeilbornTextStyles.display(
            dims.nameSize,
            color: VeilbornColors.boneWhite,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        SizedBox(height: dims.padding * 0.5),

        // Stats row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _statChip('⚔', card.attack.toString(), VeilbornColors.veilCrimson, dims),
            _statChip('🛡', card.maxDefense.toString(), VeilbornColors.revenantSilver, dims),
            _statChip('⚡', card.definition.speed.toString(), VeilbornColors.veilGold, dims),
            _manaCost(dims),
          ],
        ),

        // Ability (full size only)
        if (size == CardSize.full && card.definition.hasAbility) ...[
          SizedBox(height: dims.padding * 0.5),
          _abilityRow(dims),
        ],

        // XP bar (full and compact)
        if (size == CardSize.full || size == CardSize.compact) ...[
          SizedBox(height: dims.padding * 0.5),
          _xpBar(rarityColor, dims),
        ],
      ],
    );
  }

  Widget _artPlaceholder(Color typeColor) {
    return Container(
      color: VeilbornColors.voidDark,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _typeIcon(card.definition.cardType),
              color: typeColor.withOpacity(0.4),
              size: 36,
            ),
            const SizedBox(height: 4),
            Text(
              card.definition.cardType.label.toUpperCase(),
              style: VeilbornTextStyles.ui(9, color: typeColor.withOpacity(0.4)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeBadge(Color typeColor, _CardDims dims) {
    if (size == CardSize.tiny || size == CardSize.mini) {
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: typeColor,
          shape: BoxShape.circle,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: typeColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: typeColor.withOpacity(0.5), width: 1),
      ),
      child: Text(
        card.definition.cardType.label.substring(0, 3).toUpperCase(),
        style: VeilbornTextStyles.ui(8, color: typeColor),
      ),
    );
  }

  Widget _levelBadge(_CardDims dims) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: VeilbornColors.veilGold.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: VeilbornColors.veilGold.withOpacity(0.6), width: 1),
      ),
      child: Text(
        'LV${card.level}',
        style: VeilbornTextStyles.ui(8, color: VeilbornColors.veilGold),
      ),
    );
  }

  Widget _statChip(String icon, String value, Color color, _CardDims dims) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: TextStyle(fontSize: dims.statSize - 2)),
        const SizedBox(width: 2),
        Text(value, style: VeilbornTextStyles.stat(dims.statSize, color: color)),
      ],
    );
  }

  Widget _manaCost(_CardDims dims) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: VeilbornColors.spectreViolet.withOpacity(0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VeilbornColors.spectreViolet.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.water_drop, size: dims.statSize - 1, color: VeilbornColors.spectreViolet),
          const SizedBox(width: 2),
          Text(
            card.definition.manaCost.toString(),
            style: VeilbornTextStyles.stat(dims.statSize, color: VeilbornColors.spectreViolet),
          ),
        ],
      ),
    );
  }

  Widget _abilityRow(_CardDims dims) {
    if (!card.definition.hasAbility) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: VeilbornColors.hollow.withOpacity(0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        card.definition.abilityDesc ?? '',
        style: VeilbornTextStyles.body(10, color: VeilbornColors.ghostSilver, italic: true),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _xpBar(Color rarityColor, _CardDims dims) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'LV ${card.level}',
              style: VeilbornTextStyles.ui(9, color: VeilbornColors.ashGrey),
            ),
            if (card.level < 5)
              Text(
                '${card.xp}/${card.xpToNextLevel}',
                style: VeilbornTextStyles.ui(9, color: VeilbornColors.ashGrey),
              ),
          ],
        ),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: card.xpProgress,
            backgroundColor: VeilbornColors.hollow,
            valueColor: AlwaysStoppedAnimation(rarityColor),
            minHeight: 3,
          ),
        ),
      ],
    );
  }

  Gradient _cardGradient(Rarity rarity) {
    switch (rarity) {
      case Rarity.legendary:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1A00), Color(0xFF1A0D00), Color(0xFF2A1800)],
        );
      case Rarity.epic:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A0A2E), Color(0xFF0D0D1A)],
        );
      case Rarity.rare:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A1A2E), Color(0xFF0D0D1A)],
        );
      default:
        return VeilbornColors.cardGradient;
    }
  }

  IconData _typeIcon(CardType type) {
    switch (type) {
      case CardType.specter: return Icons.blur_on;
      case CardType.revenant: return Icons.shield;
      case CardType.phantom: return Icons.auto_awesome;
      case CardType.behemoth: return Icons.whatshot;
    }
  }

  _CardDims _dimensions(CardSize size) {
    switch (size) {
      case CardSize.full:
        return const _CardDims(width: 200, height: 300, radius: 12, padding: 10, nameSize: 13, statSize: 12);
      case CardSize.compact:
        return const _CardDims(width: 120, height: 180, radius: 10, padding: 7, nameSize: 11, statSize: 10);
      case CardSize.mini:
        return const _CardDims(width: 72, height: 104, radius: 8, padding: 5, nameSize: 9, statSize: 9);
      case CardSize.tiny:
        return const _CardDims(width: 48, height: 68, radius: 6, padding: 4, nameSize: 8, statSize: 8);
    }
  }
}

class _CardDims {
  final double width;
  final double height;
  final double radius;
  final double padding;
  final double nameSize;
  final double statSize;
  const _CardDims({
    required this.width,
    required this.height,
    required this.radius,
    required this.padding,
    required this.nameSize,
    required this.statSize,
  });
}
