import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/models.dart';
import '../../config/theme.dart';

// =============================================================================
// NarrationPanel — The DM narration display
// Slides up after each round with animated typewriter text,
// round title, key moment, and battle scene image.
// =============================================================================

class NarrationPanel extends StatefulWidget {
  final RoundResult result;
  final VoidCallback onDismiss;

  const NarrationPanel({
    super.key,
    required this.result,
    required this.onDismiss,
  });

  @override
  State<NarrationPanel> createState() => _NarrationPanelState();
}

class _NarrationPanelState extends State<NarrationPanel>
    with SingleTickerProviderStateMixin {
  String _displayedText = '';
  bool _textComplete = false;

  @override
  void initState() {
    super.initState();
    _animateText();
  }

  void _animateText() async {
    final fullText = widget.result.narrationText ?? '';
    if (fullText.isEmpty) {
      setState(() { _textComplete = true; });
      return;
    }

    // Typewriter effect — reveal text char by char
    for (int i = 0; i <= fullText.length; i++) {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 18));
      setState(() {
        _displayedText = fullText.substring(0, i);
        _textComplete = i == fullText.length;
      });
    }
  }

  void _skipToEnd() {
    setState(() {
      _displayedText = widget.result.narrationText ?? '';
      _textComplete = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _textComplete ? null : _skipToEnd,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D0D1A), Color(0xFF080810)],
          ),
          border: Border(
            top: BorderSide(color: VeilbornColors.hollow, width: 1),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: VeilbornColors.hollow,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Round title
                      _buildRoundTitle(),
                      const SizedBox(height: 16),

                      // Battle scene image
                      if (widget.result.imageUrl != null)
                        _buildBattleImage(),

                      const SizedBox(height: 16),

                      // Narration text (typewriter)
                      _buildNarrationText(),

                      // Key moment
                      if (_textComplete && widget.result.narrationKeyMoment != null)
                        _buildKeyMoment().animate().fadeIn(duration: 600.ms),

                      // Combat log summary
                      if (_textComplete)
                        _buildCombatLog().animate().fadeIn(duration: 800.ms, delay: 200.ms),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // Continue button
              if (_textComplete)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: widget.onDismiss,
                      child: const Text('CONTINUE'),
                    ),
                  ),
                ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.3, end: 0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoundTitle() {
    final toneColor = _toneColor(widget.result.narrationTone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Round badge
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: toneColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: toneColor.withOpacity(0.4)),
              ),
              child: Text(
                'ROUND ${widget.result.roundNumber}',
                style: VeilbornTextStyles.ui(10, color: toneColor),
              ),
            ),
            if (widget.result.veilCollapse) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: VeilbornColors.veilCrimson.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: VeilbornColors.veilCrimson.withOpacity(0.6),
                  ),
                ),
                child: Text(
                  'VEIL COLLAPSE',
                  style: VeilbornTextStyles.ui(10, color: VeilbornColors.veilCrimson),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // Title
        Text(
          widget.result.narrationTitle ?? 'The Rift Stirs',
          style: VeilbornTextStyles.display(22),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.2, end: 0);
  }

  Widget _buildBattleImage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: widget.result.imageUrl!,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: VeilbornColors.voidDark,
                child: const Center(
                  child: CircularProgressIndicator(
                    color: VeilbornColors.spectreViolet,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
            // Bottom gradient
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 60,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xFF080810), Colors.transparent],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 600.ms, delay: 300.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildNarrationText() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VeilbornColors.rifted.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VeilbornColors.hollow.withOpacity(0.5)),
      ),
      child: Text(
        _displayedText,
        style: VeilbornTextStyles.body(16, italic: true),
      ),
    );
  }

  Widget _buildKeyMoment() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VeilbornColors.veilGold.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VeilbornColors.veilGold.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.star, color: VeilbornColors.veilGold, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.result.narrationKeyMoment!,
              style: VeilbornTextStyles.body(14, color: VeilbornColors.veilGoldLight),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCombatLog() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('COMBAT LOG', style: VeilbornTextStyles.ui(11, color: VeilbornColors.ashGrey)),
        const SizedBox(height: 8),
        ...widget.result.events.map((e) => _buildEventRow(e)),
      ],
    );
  }

  Widget _buildEventRow(CombatEvent event) {
    final advantageColor = event.isAdvantage
        ? VeilbornColors.veilCrimson
        : event.isDisadvantage
            ? VeilbornColors.revenantSilver
            : VeilbornColors.ashGrey;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Event number
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: VeilbornColors.hollow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${event.order}',
              style: VeilbornTextStyles.ui(9, color: VeilbornColors.ashGrey),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: VeilbornTextStyles.body(13),
                children: [
                  TextSpan(
                    text: event.attackerName,
                    style: TextStyle(
                      color: VeilbornColors.typeColor(event.attackerType),
                      fontFamily: 'Cinzel',
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: ' → ',
                    style: TextStyle(color: VeilbornColors.ashGrey),
                  ),
                  TextSpan(
                    text: event.defenderName,
                    style: TextStyle(
                      color: VeilbornColors.typeColor(event.defenderType),
                      fontFamily: 'Cinzel',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Damage chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: advantageColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: advantageColor.withOpacity(0.4)),
            ),
            child: Text(
              '-${event.damageDealt}',
              style: VeilbornTextStyles.stat(12, color: advantageColor),
            ),
          ),
          // Destroyed icon
          if (event.defenderDestroyed) ...[
            const SizedBox(width: 4),
            const Icon(Icons.close, color: VeilbornColors.veilCrimson, size: 14),
          ],
        ],
      ),
    );
  }

  Color _toneColor(String? tone) {
    switch (tone) {
      case 'devastating': return VeilbornColors.veilCrimson;
      case 'triumphant': return VeilbornColors.veilGold;
      case 'chaotic': return VeilbornColors.spectreViolet;
      case 'grim': return VeilbornColors.ashGrey;
      default: return VeilbornColors.revenantSilver; // tense
    }
  }
}
