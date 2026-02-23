// =============================================================================
// Veilborn — Dart Models
// Mirror of Python engine/models.py and DB schema.
// These are plain Dart classes (no codegen dependency for portability).
// =============================================================================

enum CardType { specter, revenant, phantom, behemoth }
enum Rarity { common, rare, epic, legendary }
enum GamePhase { draw, mana, placement, reveal, resolve, cleanup, matchOver }
enum RowPosition { front, back }
enum MatchStatus { waiting, active, completed, abandoned, draw }

extension CardTypeX on CardType {
  String get label => name[0].toUpperCase() + name.substring(1);
  String get beats {
    switch (this) {
      case CardType.specter: return 'Behemoth';
      case CardType.revenant: return 'Specter';
      case CardType.phantom: return 'Revenant';
      case CardType.behemoth: return 'Phantom';
    }
  }
  String get weakTo {
    switch (this) {
      case CardType.specter: return 'Revenant';
      case CardType.revenant: return 'Phantom';
      case CardType.phantom: return 'Behemoth';
      case CardType.behemoth: return 'Specter';
    }
  }
}

extension RarityX on Rarity {
  String get label => name[0].toUpperCase() + name.substring(1);
  int get sortOrder => index;
}

// ---------------------------------------------------------------------------
// Card Definition (from card_definitions table)
// ---------------------------------------------------------------------------

class CardDefinition {
  final String id;
  final String name;
  final CardType cardType;
  final Rarity rarity;
  final int baseAttack;
  final int baseDefense;
  final int speed;
  final int manaCost;
  final String? abilityTrigger;
  final String? abilityEffect;
  final double? abilityValue;
  final String? abilityDesc;
  final String lore;
  final String artUrl;

  const CardDefinition({
    required this.id,
    required this.name,
    required this.cardType,
    required this.rarity,
    required this.baseAttack,
    required this.baseDefense,
    required this.speed,
    required this.manaCost,
    this.abilityTrigger,
    this.abilityEffect,
    this.abilityValue,
    this.abilityDesc,
    required this.lore,
    required this.artUrl,
  });

  bool get hasAbility => abilityEffect != null;

  factory CardDefinition.fromJson(Map<String, dynamic> json) => CardDefinition(
    id: json['id'] as String,
    name: json['name'] as String,
    cardType: CardType.values.firstWhere(
      (e) => e.label == json['card_type'],
      orElse: () => CardType.specter,
    ),
    rarity: Rarity.values.firstWhere(
      (e) => e.label == json['rarity'],
      orElse: () => Rarity.common,
    ),
    baseAttack: json['base_attack'] as int,
    baseDefense: json['base_defense'] as int,
    speed: json['speed'] as int,
    manaCost: json['mana_cost'] as int,
    abilityTrigger: json['ability_trigger'] as String?,
    abilityEffect: json['ability_effect'] as String?,
    abilityValue: (json['ability_value'] as num?)?.toDouble(),
    abilityDesc: json['ability_desc'] as String?,
    lore: json['lore'] as String? ?? '',
    artUrl: json['art_url'] as String? ?? '',
  );
}

// ---------------------------------------------------------------------------
// Owned Card (from player_cards joined with card_definitions)
// ---------------------------------------------------------------------------

class OwnedCard {
  final String instanceId;        // player_cards.id
  final CardDefinition definition;
  final int level;
  final int xp;
  final int consecutiveLosses;
  final bool isDormant;
  final DateTime? dormantUntil;

  const OwnedCard({
    required this.instanceId,
    required this.definition,
    this.level = 1,
    this.xp = 0,
    this.consecutiveLosses = 0,
    this.isDormant = false,
    this.dormantUntil,
  });

  // Computed stats with level bonuses (matches Python engine)
  int get attack => definition.baseAttack + (level - 1);
  int get maxDefense => definition.baseDefense + (level - 1) * 2;
  int get xpToNextLevel {
    const thresholds = {1: 100, 2: 250, 3: 500, 4: 1000};
    return thresholds[level] ?? 9999;
  }
  double get xpProgress => level >= 5 ? 1.0 : xp / xpToNextLevel;

  factory OwnedCard.fromJson(Map<String, dynamic> json) {
    final defJson = json['card_definitions'] as Map<String, dynamic>? ?? json;
    return OwnedCard(
      instanceId: json['id'] as String,
      definition: CardDefinition.fromJson(defJson),
      level: json['level'] as int? ?? 1,
      xp: json['xp'] as int? ?? 0,
      consecutiveLosses: json['consecutive_losses'] as int? ?? 0,
      isDormant: json['is_dormant'] as bool? ?? false,
      dormantUntil: json['dormant_until'] != null
        ? DateTime.tryParse(json['dormant_until'] as String)
        : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Player Profile
// ---------------------------------------------------------------------------

class PlayerProfile {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final int veilweaverLevel;
  final int totalXp;
  final int shards;
  final int crystals;
  final int matchesPlayed;
  final int matchesWon;
  final int eloRating;
  final int winStreak;
  final int bestWinStreak;

  const PlayerProfile({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.veilweaverLevel,
    required this.totalXp,
    required this.shards,
    required this.crystals,
    required this.matchesPlayed,
    required this.matchesWon,
    required this.eloRating,
    required this.winStreak,
    required this.bestWinStreak,
  });

  double get winRate => matchesPlayed == 0 ? 0 : matchesWon / matchesPlayed;

  factory PlayerProfile.fromJson(Map<String, dynamic> json) => PlayerProfile(
    id: json['id'] as String,
    username: json['username'] as String,
    displayName: json['display_name'] as String,
    avatarUrl: json['avatar_url'] as String?,
    veilweaverLevel: json['veilweaver_level'] as int? ?? 1,
    totalXp: json['total_xp'] as int? ?? 0,
    shards: json['shards'] as int? ?? 0,
    crystals: json['crystals'] as int? ?? 0,
    matchesPlayed: json['matches_played'] as int? ?? 0,
    matchesWon: json['matches_won'] as int? ?? 0,
    eloRating: json['elo_rating'] as int? ?? 1000,
    winStreak: json['win_streak'] as int? ?? 0,
    bestWinStreak: json['best_win_streak'] as int? ?? 0,
  );
}

// ---------------------------------------------------------------------------
// Deck
// ---------------------------------------------------------------------------

class Deck {
  final String id;
  final String name;
  final bool isActive;
  final List<OwnedCard> cards;
  final DateTime createdAt;

  const Deck({
    required this.id,
    required this.name,
    required this.isActive,
    required this.cards,
    required this.createdAt,
  });

  bool get isValid => cards.length == 10;
  int get cardCount => cards.length;

  factory Deck.fromJson(Map<String, dynamic> json) => Deck(
    id: json['id'] as String,
    name: json['name'] as String,
    isActive: json['is_active'] as bool? ?? false,
    cards: [],
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
  );
}

// ---------------------------------------------------------------------------
// Match
// ---------------------------------------------------------------------------

class Match {
  final String id;
  final String player1Id;
  final String? player2Id;
  final String? winnerId;
  final MatchStatus status;
  final int player1Score;
  final int player2Score;
  final int currentRound;
  final GamePhase currentPhase;
  final String realtimeChannel;
  final DateTime createdAt;
  final DateTime? completedAt;

  const Match({
    required this.id,
    required this.player1Id,
    this.player2Id,
    this.winnerId,
    required this.status,
    required this.player1Score,
    required this.player2Score,
    required this.currentRound,
    required this.currentPhase,
    required this.realtimeChannel,
    required this.createdAt,
    this.completedAt,
  });

  factory Match.fromJson(Map<String, dynamic> json) => Match(
    id: json['id'] as String,
    player1Id: json['player1_id'] as String,
    player2Id: json['player2_id'] as String?,
    winnerId: json['winner_id'] as String?,
    status: MatchStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => MatchStatus.waiting,
    ),
    player1Score: json['player1_score'] as int? ?? 0,
    player2Score: json['player2_score'] as int? ?? 0,
    currentRound: json['current_round'] as int? ?? 1,
    currentPhase: GamePhase.draw,
    realtimeChannel: json['realtime_channel'] as String? ?? '',
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    completedAt: json['completed_at'] != null
      ? DateTime.tryParse(json['completed_at'] as String)
      : null,
  );
}

// ---------------------------------------------------------------------------
// Board placement (local game state)
// ---------------------------------------------------------------------------

class BoardPlacement {
  final OwnedCard card;
  final int col;
  final RowPosition row;
  final String playerId;
  final bool faceDown;
  int currentHp;
  int positionBonus;

  BoardPlacement({
    required this.card,
    required this.col,
    required this.row,
    required this.playerId,
    required this.currentHp,
    this.faceDown = true,
    this.positionBonus = 0,
  });
}

// ---------------------------------------------------------------------------
// Combat event (from BattleLog)
// ---------------------------------------------------------------------------

class CombatEvent {
  final int order;
  final String attackerName;
  final String attackerType;
  final int attackerLevel;
  final String attackerOwner;
  final String defenderName;
  final String defenderType;
  final int defenderLevel;
  final String defenderOwner;
  final String typeAdvantage;
  final int damageDealt;
  final int positionBonus;
  final bool defenderDestroyed;
  final String? abilityName;
  final String? abilityDesc;

  const CombatEvent({
    required this.order,
    required this.attackerName,
    required this.attackerType,
    required this.attackerLevel,
    required this.attackerOwner,
    required this.defenderName,
    required this.defenderType,
    required this.defenderLevel,
    required this.defenderOwner,
    required this.typeAdvantage,
    required this.damageDealt,
    required this.positionBonus,
    required this.defenderDestroyed,
    this.abilityName,
    this.abilityDesc,
  });

  bool get isAdvantage => typeAdvantage.contains('advantage (1.5x)');
  bool get isDisadvantage => typeAdvantage.contains('disadvantage');

  factory CombatEvent.fromJson(Map<String, dynamic> json) {
    final attacker = json['attacker'] as Map<String, dynamic>;
    final defender = json['defender'] as Map<String, dynamic>;
    final ability = json['ability'] as Map<String, dynamic>?;
    return CombatEvent(
      order: json['order'] as int,
      attackerName: attacker['name'] as String,
      attackerType: attacker['type'] as String,
      attackerLevel: attacker['level'] as int,
      attackerOwner: attacker['owner'] as String,
      defenderName: defender['name'] as String,
      defenderType: defender['type'] as String,
      defenderLevel: defender['level'] as int,
      defenderOwner: defender['owner'] as String,
      typeAdvantage: json['type_advantage'] as String,
      damageDealt: json['damage_dealt'] as int,
      positionBonus: json['position_bonus'] as int,
      defenderDestroyed: json['defender_destroyed'] as bool,
      abilityName: ability?['name'] as String?,
      abilityDesc: ability?['description'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Round result (from match_rounds table)
// ---------------------------------------------------------------------------

class RoundResult {
  final int roundNumber;
  final String? narrationTitle;
  final String? narrationText;
  final String? narrationTone;
  final String? narrationKeyMoment;
  final String? imageUrl;
  final List<CombatEvent> events;
  final int p1SurvivingDefense;
  final int p2SurvivingDefense;
  final String? roundWinnerId;
  final int pointsAwarded;
  final bool veilCollapse;

  const RoundResult({
    required this.roundNumber,
    this.narrationTitle,
    this.narrationText,
    this.narrationTone,
    this.narrationKeyMoment,
    this.imageUrl,
    required this.events,
    required this.p1SurvivingDefense,
    required this.p2SurvivingDefense,
    this.roundWinnerId,
    required this.pointsAwarded,
    required this.veilCollapse,
  });

  factory RoundResult.fromJson(Map<String, dynamic> json) {
    final battleLog = json['battle_log'] as Map<String, dynamic>? ?? {};
    final combatEvents = (battleLog['combat_events'] as List<dynamic>? ?? [])
        .map((e) => CombatEvent.fromJson(e as Map<String, dynamic>))
        .toList();
    return RoundResult(
      roundNumber: json['round_number'] as int,
      narrationTitle: json['narration_title'] as String?,
      narrationText: json['narration_text'] as String?,
      narrationTone: json['narration_tone'] as String?,
      narrationKeyMoment: json['narration_key_moment'] as String?,
      imageUrl: json['image_url'] as String?,
      events: combatEvents,
      p1SurvivingDefense: json['p1_surviving_defense'] as int? ?? 0,
      p2SurvivingDefense: json['p2_surviving_defense'] as int? ?? 0,
      roundWinnerId: json['round_winner_id'] as String?,
      pointsAwarded: json['points_awarded'] as int? ?? 0,
      veilCollapse: json['veil_collapse'] as bool? ?? false,
    );
  }
}

// ---------------------------------------------------------------------------
// Card pack
// ---------------------------------------------------------------------------

class CardPack {
  final String id;
  final String name;
  final String description;
  final int cardsPerPack;
  final int? shardCost;
  final int? crystalCost;
  final String? guaranteedRarity;
  final String artUrl;

  const CardPack({
    required this.id,
    required this.name,
    required this.description,
    required this.cardsPerPack,
    this.shardCost,
    this.crystalCost,
    this.guaranteedRarity,
    required this.artUrl,
  });

  factory CardPack.fromJson(Map<String, dynamic> json) => CardPack(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    cardsPerPack: json['cards_per_pack'] as int? ?? 5,
    shardCost: json['shard_cost'] as int?,
    crystalCost: json['crystal_cost'] as int?,
    guaranteedRarity: json['guaranteed_rarity'] as String?,
    artUrl: json['art_url'] as String? ?? '',
  );
}
