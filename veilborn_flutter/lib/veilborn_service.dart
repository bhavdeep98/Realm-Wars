import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

// =============================================================================
// Veilborn — Supabase Service
// Single access point for all backend operations.
// =============================================================================

class VeilbornService {
  final SupabaseClient _client;

  VeilbornService(this._client);

  static VeilbornService get instance =>
      VeilbornService(Supabase.instance.client);

  // ── Auth ──────────────────────────────────────────────────────────────────

  User? get currentUser => _client.auth.currentUser;
  String? get currentUserId => _client.auth.currentUser?.id;
  bool get isLoggedIn => currentUser != null;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
    required String displayName,
  }) async {
    return _client.auth.signUp(
      email: email,
      password: password,
      data: {'username': username, 'display_name': displayName},
    );
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  // ── Profile ───────────────────────────────────────────────────────────────

  Future<PlayerProfile?> getProfile(String userId) async {
    final data = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return data != null ? PlayerProfile.fromJson(data) : null;
  }

  Future<List<Map<String, dynamic>>> getLeaderboard({int limit = 50}) async {
    return await _client
        .from('profiles')
        .select('username, display_name, elo_rating, matches_won, matches_played, veilweaver_level')
        .order('elo_rating', ascending: false)
        .limit(limit);
  }

  // ── Cards ──────────────────────────────────────────────────────────────────

  Future<List<OwnedCard>> getMyCards() async {
    final userId = currentUserId;
    if (userId == null) return [];

    final data = await _client
        .from('player_cards')
        .select('*, card_definitions(*)')
        .eq('player_id', userId)
        .order('acquired_at', ascending: false);

    return (data as List).map((row) => OwnedCard.fromJson(row)).toList();
  }

  Future<List<CardDefinition>> getAllCardDefinitions() async {
    final data = await _client
        .from('card_definitions')
        .select()
        .eq('is_active', true)
        .order('rarity');
    return (data as List).map((row) => CardDefinition.fromJson(row)).toList();
  }

  // ── Decks ──────────────────────────────────────────────────────────────────

  Future<List<Deck>> getMyDecks() async {
    final userId = currentUserId;
    if (userId == null) return [];

    final data = await _client
        .from('decks')
        .select()
        .eq('player_id', userId)
        .order('created_at', ascending: false);

    return (data as List).map((row) => Deck.fromJson(row)).toList();
  }

  Future<List<OwnedCard>> getDeckCards(String deckId) async {
    final data = await _client
        .from('deck_cards')
        .select('player_cards(*, card_definitions(*))')
        .eq('deck_id', deckId)
        .order('slot_order');

    return (data as List)
        .map((row) => OwnedCard.fromJson(row['player_cards']))
        .toList();
  }

  Future<String> createDeck(String name) async {
    final userId = currentUserId!;
    final data = await _client
        .from('decks')
        .insert({'player_id': userId, 'name': name, 'is_active': false})
        .select()
        .single();
    return data['id'] as String;
  }

  Future<void> addCardToDeck(String deckId, String playerCardId, int slotOrder) async {
    await _client.from('deck_cards').insert({
      'deck_id': deckId,
      'player_card_id': playerCardId,
      'slot_order': slotOrder,
    });
  }

  Future<void> removeCardFromDeck(String deckId, String playerCardId) async {
    await _client
        .from('deck_cards')
        .delete()
        .eq('deck_id', deckId)
        .eq('player_card_id', playerCardId);
  }

  Future<void> setActiveDeck(String deckId) async {
    final userId = currentUserId!;
    await _client
        .from('decks')
        .update({'is_active': true})
        .eq('id', deckId)
        .eq('player_id', userId);
  }

  // ── Matchmaking ────────────────────────────────────────────────────────────

  Future<String> findOrCreateMatch() async {
    final userId = currentUserId!;

    // Get active deck
    final deckData = await _client
        .from('decks')
        .select('id')
        .eq('player_id', userId)
        .eq('is_active', true)
        .maybeSingle();

    if (deckData == null) throw Exception('No active deck set');
    final deckId = deckData['id'] as String;

    // Get ELO
    final profileData = await _client
        .from('profiles')
        .select('elo_rating')
        .eq('id', userId)
        .single();
    final elo = profileData['elo_rating'] as int;

    // Find waiting match in ELO range
    final waiting = await _client
        .from('matches')
        .select('id')
        .eq('status', 'waiting')
        .gte('elo_bracket', elo - 150)
        .lte('elo_bracket', elo + 150)
        .neq('player1_id', userId)
        .order('created_at')
        .limit(1)
        .maybeSingle();

    if (waiting != null) {
      // Join existing match
      final matchId = waiting['id'] as String;
      await _client.from('matches').update({
        'player2_id': userId,
        'player2_deck_id': deckId,
        'status': 'active',
        'started_at': DateTime.now().toIso8601String(),
      }).eq('id', matchId);
      return matchId;
    }

    // Create new match and wait
    final matchId = '${DateTime.now().millisecondsSinceEpoch}';
    await _client.from('matches').insert({
      'player1_id': userId,
      'player1_deck_id': deckId,
      'elo_bracket': elo,
      'status': 'waiting',
      'realtime_channel': 'match:$matchId',
    });
    return matchId;
  }

  Future<Match?> getMatch(String matchId) async {
    final data = await _client
        .from('matches')
        .select()
        .eq('id', matchId)
        .maybeSingle();
    return data != null ? Match.fromJson(data) : null;
  }

  Future<List<Match>> getMatchHistory({int limit = 20}) async {
    final userId = currentUserId;
    if (userId == null) return [];

    final data = await _client
        .from('matches')
        .select()
        .or('player1_id.eq.$userId,player2_id.eq.$userId')
        .inFilter('status', ['completed', 'draw'])
        .order('completed_at', ascending: false)
        .limit(limit);

    return (data as List).map((row) => Match.fromJson(row)).toList();
  }

  // ── Match Placements ────────────────────────────────────────────────────────

  Future<void> submitPlacement({
    required String matchId,
    required int roundNumber,
    required String playerCardId,
    required int col,
    required String row,
    required int manaSpent,
  }) async {
    final userId = currentUserId!;
    await _client.from('match_placements').insert({
      'match_id': matchId,
      'round_number': roundNumber,
      'player_id': userId,
      'player_card_id': playerCardId,
      'col': col,
      'row': row,
      'mana_spent': manaSpent,
      'face_down': true,
    });
  }

  // Resolve round via Edge Function
  Future<Map<String, dynamic>> resolveRound({
    required String matchId,
    required int roundNumber,
  }) async {
    final response = await _client.functions.invoke(
      'resolve-round',
      body: {'match_id': matchId, 'round_number': roundNumber},
    );
    if (response.data == null) throw Exception('Failed to resolve round');
    return response.data as Map<String, dynamic>;
  }

  // ── Match Rounds ────────────────────────────────────────────────────────────

  Future<List<RoundResult>> getMatchRounds(String matchId) async {
    final data = await _client
        .from('match_rounds')
        .select()
        .eq('match_id', matchId)
        .order('round_number');
    return (data as List).map((row) => RoundResult.fromJson(row)).toList();
  }

  // ── Realtime ───────────────────────────────────────────────────────────────

  RealtimeChannel subscribeToMatch(
    String matchId, {
    required void Function(Map<String, dynamic>) onRoundResolved,
    required void Function(Map<String, dynamic>) onMatchStateChanged,
  }) {
    return _client
        .channel('match:$matchId')
        .onBroadcast(
          event: 'round_resolved',
          callback: (payload) => onRoundResolved(payload),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'matches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: matchId,
          ),
          callback: (payload) => onMatchStateChanged(payload.newRecord),
        )
        .subscribe();
  }

  void unsubscribeFromMatch(RealtimeChannel channel) {
    _client.removeChannel(channel);
  }

  // ── Shop ───────────────────────────────────────────────────────────────────

  Future<List<CardPack>> getAvailablePacks() async {
    final data = await _client
        .from('card_packs')
        .select()
        .eq('is_active', true);
    return (data as List).map((row) => CardPack.fromJson(row)).toList();
  }

  Future<List<String>> openPack({
    required String packId,
    required String currencyType,
    String? revenuecatTx,
  }) async {
    final response = await _client.functions.invoke(
      'open-pack',
      body: {
        'pack_id': packId,
        'currency_type': currencyType,
        if (revenuecatTx != null) 'revenuecat_tx': revenuecatTx,
      },
    );
    final data = response.data as Map<String, dynamic>;
    return List<String>.from(data['cards_awarded'] as List);
  }
}
