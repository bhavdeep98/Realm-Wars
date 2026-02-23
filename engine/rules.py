"""
Veilborn Rules Engine — Combat Resolution
This is the deterministic core. No randomness, no AI. Every outcome is explainable.
The DM agent consumes RoundResult but never influences it.
"""

from __future__ import annotations
from typing import Optional
from .models import (
    GameState, GamePhase, Player, Row, Board, BoardCard,
    CardInstance, CardType, TYPE_MATCHUP, AbilityEffect, AbilityTrigger,
    CombatEvent, RoundResult, PlayerState
)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

FLANKING_THRESHOLD = 3          # Front row cards needed for flanking
FLANKING_BONUS = 2              # Extra attack when flanking
COLUMN_PRESSURE_BONUS = 1       # Bonus when facing type-disadvantaged opponent
MANA_PER_TURN = 1
MANA_CAP = 8
VEIL_SURGE_MAX = 3
ROUNDS_PER_MATCH = 5
WIN_SCORE = 3
DORMANCY_LOSS_THRESHOLD = 3


# ---------------------------------------------------------------------------
# Phase: Draw
# ---------------------------------------------------------------------------

def phase_draw(state: GameState, draw_to: int = 5) -> GameState:
    """Both players draw until hand size is draw_to."""
    for ps in [state.player1, state.player2]:
        needed = draw_to - len(ps.hand)
        drawn = ps.deck[:needed]
        ps.deck = ps.deck[needed:]
        ps.hand.extend(drawn)
    state.phase = GamePhase.MANA
    return state


# ---------------------------------------------------------------------------
# Phase: Mana
# ---------------------------------------------------------------------------

def phase_mana(state: GameState) -> GameState:
    """Replenish mana for both players."""
    for ps in [state.player1, state.player2]:
        ps.mana = min(ps.mana + MANA_PER_TURN, MANA_CAP)
    state.phase = GamePhase.PLACEMENT
    return state


# ---------------------------------------------------------------------------
# Phase: Placement validation
# ---------------------------------------------------------------------------

def validate_placement(
    state: GameState,
    player: Player,
    placements: list[dict]
) -> tuple[bool, str]:
    """
    Validate a player's placement intentions.
    placements: [{"card_instance_id": str, "col": int, "row": Row}]
    Returns (valid, error_message)
    """
    ps = state.get_player_state(player)
    hand_ids = {c.instance_id for c in ps.hand}
    total_mana = 0
    placed_cells = set()

    for p in placements:
        cid = p["card_instance_id"]
        col = p["col"]
        row = p["row"]

        # Card must be in hand
        card = next((c for c in ps.hand if c.instance_id == cid), None)
        if card is None:
            return False, f"Card {cid} not in hand"

        # Card must not be dormant
        if card.is_dormant:
            return False, f"Card {card.definition.name} is dormant"

        # Must be player's own rows
        if row not in _valid_rows_for(player):
            return False, f"Player {player} cannot place in row {row}"

        # Column must be 0–3
        if not (0 <= col <= 3):
            return False, f"Column {col} out of range"

        # Cell must not be double-used in same placement batch
        cell_key = (col, row)
        if cell_key in placed_cells:
            return False, f"Duplicate cell placement at col={col}, row={row}"
        placed_cells.add(cell_key)

        # Cell must be empty on the board
        if state.board.get(col, row, player) is not None:
            return False, f"Cell ({col}, {row}) already occupied"

        total_mana += card.definition.mana_cost

    # Mana check
    available_mana = ps.mana
    if total_mana > available_mana:
        # Check Veil Surge
        overdraft = total_mana - available_mana
        if ps.veil_surge_used or overdraft > VEIL_SURGE_MAX:
            return False, f"Insufficient mana (need {total_mana}, have {available_mana})"

    return True, ""


def apply_placement(
    state: GameState,
    player: Player,
    placements: list[dict]
) -> GameState:
    """Apply validated placements to the board (face down)."""
    ps = state.get_player_state(player)
    total_mana = 0

    for p in placements:
        cid = p["card_instance_id"]
        col = p["col"]
        row = p["row"]
        card_instance = next(c for c in ps.hand if c.instance_id == cid)

        board_card = BoardCard(
            instance=card_instance,
            current_hp=card_instance.max_defense,
            col=col,
            row=row,
            owner=player,
            face_down=True,
        )
        state.board.place(board_card)
        ps.hand.remove(card_instance)
        total_mana += card_instance.definition.mana_cost

    # Deduct mana, handle Veil Surge
    if total_mana > ps.mana:
        overdraft = total_mana - ps.mana
        ps.mana = -overdraft          # Debt, repaid next turn
        ps.veil_surge_used = True
    else:
        ps.mana -= total_mana

    return state


# ---------------------------------------------------------------------------
# Phase: Reveal
# ---------------------------------------------------------------------------

def phase_reveal(state: GameState) -> GameState:
    """Flip all face-down cards."""
    for card in state.board.all_cards():
        card.face_down = False
    state.phase = GamePhase.RESOLVE
    return state


# ---------------------------------------------------------------------------
# Phase: Resolve — the heart of the engine
# ---------------------------------------------------------------------------

def phase_resolve(state: GameState) -> tuple[GameState, RoundResult]:
    """
    Fully deterministic combat resolution.
    Returns updated state and a complete RoundResult for the DM agent.
    """
    board = state.board
    events: list[CombatEvent] = []
    event_order = 0
    veil_collapse = state.current_round == ROUNDS_PER_MATCH

    # Step 1: Apply position bonuses
    flanking_player = _apply_flanking(board)
    _apply_column_pressure(board)

    # Step 2: Veil Collapse — all attacks +50% in round 5
    if veil_collapse:
        for card in board.all_cards():
            card.position_bonus_attack += card.instance.attack // 2

    # Step 3: Sort all cards by speed descending, then attack descending
    all_cards = sorted(
        board.all_cards(),
        key=lambda c: (c.instance.definition.speed, c.effective_attack),
        reverse=True
    )

    # Step 4: Each card attacks in speed order
    dead_cards: list[BoardCard] = []

    for attacker in all_cards:
        if not attacker.is_alive:
            continue

        target = _find_target(attacker, board)
        if target is None:
            continue

        multiplier = TYPE_MATCHUP[attacker.instance.definition.card_type][
            target.instance.definition.card_type
        ]
        raw = attacker.effective_attack
        damage = int(raw * multiplier)

        # Apply ARMOR ability on defender
        if (target.instance.definition.ability and
                target.instance.definition.ability.effect == AbilityEffect.ARMOR):
            armor_val = int(target.instance.definition.ability.value)
            damage = max(0, damage - armor_val)

        target.current_hp -= damage
        event_order += 1

        ability_triggered = None
        ability_desc = None

        # Attacker LIFESTEAL
        if (attacker.instance.definition.ability and
                attacker.instance.definition.ability.trigger == AbilityTrigger.ON_ATTACK and
                attacker.instance.definition.ability.effect == AbilityEffect.LIFESTEAL):
            heal = int(damage * attacker.instance.definition.ability.value)
            attacker.current_hp = min(attacker.current_hp + heal, attacker.instance.max_defense)
            ability_triggered = "Lifesteal"
            ability_desc = f"{attacker.instance.definition.name} drained {heal} vitality"

        destroyed = not target.is_alive

        # On-death: VEIL_ECHO — deal half attack to killer
        if destroyed and (target.instance.definition.ability and
                target.instance.definition.ability.trigger == AbilityTrigger.ON_DEATH and
                target.instance.definition.ability.effect == AbilityEffect.VEIL_ECHO):
            echo_damage = target.instance.attack // 2
            attacker.current_hp -= echo_damage
            ability_triggered = "Veil Echo"
            ability_desc = f"{target.instance.definition.name} unleashed a death echo for {echo_damage} damage"

        events.append(CombatEvent(
            order=event_order,
            attacker_name=attacker.instance.definition.name,
            attacker_type=attacker.instance.definition.card_type.value,
            attacker_level=attacker.instance.level,
            attacker_owner=attacker.owner,
            defender_name=target.instance.definition.name,
            defender_type=target.instance.definition.card_type.value,
            defender_level=target.instance.level,
            defender_owner=target.owner,
            type_multiplier=multiplier,
            raw_attack=raw,
            damage_dealt=damage,
            position_bonus=attacker.position_bonus_attack,
            defender_destroyed=destroyed,
            ability_triggered=ability_triggered,
            ability_effect_description=ability_desc,
        ))

        if destroyed:
            dead_cards.append(target)

    # Step 5: Remove dead cards from board
    for dead in dead_cards:
        board.remove(dead.col, dead.row, dead.owner)

    # Step 6: Score the round
    p1_def = sum(c.current_hp for c in board.cards_for(Player.ONE))
    p2_def = sum(c.current_hp for c in board.cards_for(Player.TWO))

    p2_wiped = len(board.cards_for(Player.TWO)) == 0
    p1_wiped = len(board.cards_for(Player.ONE)) == 0

    if p1_wiped and p2_wiped:
        round_winner = None
        points = 0
    elif p2_wiped and not p1_wiped:
        round_winner = Player.ONE
        points = 2
    elif p1_wiped and not p2_wiped:
        round_winner = Player.TWO
        points = 2
    elif p1_def > p2_def:
        round_winner = Player.ONE
        points = 1
    elif p2_def > p1_def:
        round_winner = Player.TWO
        points = 1
    else:
        round_winner = None
        points = 0

    if round_winner:
        ps = state.get_player_state(round_winner)
        ps.score += points

    # Step 7: Check match winner
    match_winner = None
    if state.player1.score >= WIN_SCORE:
        match_winner = Player.ONE
    elif state.player2.score >= WIN_SCORE:
        match_winner = Player.TWO
    elif state.current_round >= ROUNDS_PER_MATCH:
        if state.player1.score > state.player2.score:
            match_winner = Player.ONE
        elif state.player2.score > state.player1.score:
            match_winner = Player.TWO
        # else: true draw (rare, may handle with sudden death later)

    state.match_winner = match_winner

    result = RoundResult(
        round_number=state.current_round,
        events=events,
        veil_collapse=veil_collapse,
        p1_surviving_defense=p1_def,
        p2_surviving_defense=p2_def,
        round_winner=round_winner,
        round_points_awarded=points,
        match_score={"player_1": state.player1.score, "player_2": state.player2.score},
        match_winner=match_winner,
        flanking_applied=flanking_player,
    )

    state.round_history.append(result)
    state.phase = GamePhase.MATCH_OVER if match_winner else GamePhase.CLEANUP
    return state, result


# ---------------------------------------------------------------------------
# Phase: Cleanup
# ---------------------------------------------------------------------------

def phase_cleanup(state: GameState) -> GameState:
    """
    - Award XP to surviving and destroyed cards
    - Update consecutive losses / dormancy
    - Clear board for next round
    - Advance round counter
    """
    board = state.board
    last_result = state.round_history[-1]

    # Determine which instances fought this round
    destroyed_names = {e.defender_name for e in last_result.events if e.defender_destroyed}
    surviving_cards = board.all_cards()
    surviving_names = {c.instance.definition.name for c in surviving_cards}

    # XP: survivors earn based on damage dealt this round
    for card in surviving_cards:
        damage_dealt = sum(
            e.damage_dealt for e in last_result.events
            if e.attacker_name == card.instance.definition.name
               and e.attacker_owner == card.owner
        )
        xp_earned = damage_dealt + (10 if card.instance.definition.name in surviving_names else 0)
        leveled = card.instance.add_xp(xp_earned)

    # XP: destroyed cards earn half of their damage dealt
    for event in last_result.events:
        if event.defender_destroyed:
            for ps in [state.player1, state.player2]:
                for card_inst in ps.deck + ps.hand:
                    if card_inst.definition.name == event.defender_name:
                        damage_dealt = sum(
                            e.damage_dealt for e in last_result.events
                            if e.attacker_name == event.defender_name
                        )
                        card_inst.add_xp(damage_dealt // 2)

    # Dormancy: track consecutive losses per card instance
    round_loser = state.opponent(last_result.round_winner) if last_result.round_winner else None
    if round_loser:
        loser_ps = state.get_player_state(round_loser)
        for card_inst in loser_ps.deck + loser_ps.hand:
            # Cards that were destroyed count as a loss
            if card_inst.definition.name in destroyed_names:
                card_inst.consecutive_losses += 1
                if card_inst.consecutive_losses >= DORMANCY_LOSS_THRESHOLD:
                    card_inst.is_dormant = True
            else:
                card_inst.consecutive_losses = 0  # Reset if survived
    
    # Surviving cards return to hand/deck for next round (board persists damage)
    # Destroyed cards go back to deck at 1 HP
    for ps in [state.player1, state.player2]:
        for card in board.cards_for(ps.player):
            # Put surviving board cards back into the hand pool (they persist)
            ps.hand.append(card.instance)

    # Clear board
    state.board = Board()

    # Mana debt repayment
    for ps in [state.player1, state.player2]:
        if ps.mana < 0:
            ps.mana = 0  # Debt cleared, but generates 0 mana this turn

    state.current_round += 1
    state.phase = GamePhase.DRAW
    return state


# ---------------------------------------------------------------------------
# Targeting Logic (deterministic)
# ---------------------------------------------------------------------------

def _find_target(attacker: BoardCard, board: Board) -> Optional[BoardCard]:
    """
    Targeting priority:
    1. Directly opposing cell (same column, opponent's front row if attacker is front)
    2. Back row in same column if front is empty (line of sight)
    3. Nearest enemy by column distance
    4. Lowest HP enemy if equidistant
    """
    opponent = Player.TWO if attacker.owner == Player.ONE else Player.ONE

    # Back row protection: back row can only be targeted if front row in same column is empty
    def is_targetable(card: BoardCard) -> bool:
        if card.row == Row.BACK:
            front_blocker = board.get(card.col, Row.FRONT, card.owner)
            return front_blocker is None
        return True

    # Priority 1: Direct opponent in same column
    opp_front_row = Row.FRONT if attacker.row == Row.FRONT else Row.BACK
    # Attacker in front row → targets opponent's front row first
    direct = board.get(attacker.col, Row.FRONT, opponent)
    if direct and direct.is_alive and is_targetable(direct):
        return direct

    # Priority 2: Back row in same column (line of sight)
    back_direct = board.get(attacker.col, Row.BACK, opponent)
    if back_direct and back_direct.is_alive and is_targetable(back_direct):
        return back_direct

    # Priority 3: Nearest enemy by column distance, then lowest HP
    enemies = [
        c for c in board.cards_for(opponent)
        if c.is_alive and is_targetable(c)
    ]
    if not enemies:
        return None

    enemies.sort(key=lambda c: (abs(c.col - attacker.col), c.current_hp))
    return enemies[0]


# ---------------------------------------------------------------------------
# Position Bonus Logic
# ---------------------------------------------------------------------------

def _apply_flanking(board: Board) -> Optional[Player]:
    """
    If a player occupies 3+ front row columns and opponent has ≤2,
    that player's front row cards get +FLANKING_BONUS attack.
    Returns the player who got flanking, or None.
    """
    flanking_player = None
    for player in [Player.ONE, Player.TWO]:
        opponent = Player.TWO if player == Player.ONE else Player.ONE
        my_front = board.front_row_for(player)
        opp_front = board.front_row_for(opponent)
        my_cols = {c.col for c in my_front}
        opp_cols = {c.col for c in opp_front}
        if len(my_cols) >= FLANKING_THRESHOLD and len(opp_cols) <= 2:
            for card in my_front:
                card.position_bonus_attack += FLANKING_BONUS
            flanking_player = player
    return flanking_player


def _apply_column_pressure(board: Board):
    """
    A card facing an opponent it has type advantage over in the same column
    gains +COLUMN_PRESSURE_BONUS attack.
    """
    for player in [Player.ONE, Player.TWO]:
        opponent = Player.TWO if player == Player.ONE else Player.ONE
        for card in board.front_row_for(player):
            opp_card = board.get(card.col, Row.FRONT, opponent)
            if opp_card:
                mult = TYPE_MATCHUP[card.instance.definition.card_type][
                    opp_card.instance.definition.card_type
                ]
                if mult == 1.5:
                    card.position_bonus_attack += COLUMN_PRESSURE_BONUS


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _valid_rows_for(player: Player) -> list[Row]:
    return [Row.FRONT, Row.BACK]


def opponent_of(player: Player) -> Player:
    return Player.TWO if player == Player.ONE else Player.ONE
