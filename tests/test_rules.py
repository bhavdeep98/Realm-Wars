"""
Veilborn Rules Engine — Test Suite
Tests cover: type advantages, positioning, mana, targeting, win conditions, XP.
Every test is deterministic — no randomness, no AI. Outcomes are verifiable.
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import uuid
from engine.models import (
    GameState, Player, Row, PlayerState, CardInstance,
    CardType, TYPE_MATCHUP, BoardCard
)
from engine.rules import (
    phase_draw, phase_mana, apply_placement, phase_reveal,
    phase_resolve, phase_cleanup, validate_placement,
    FLANKING_BONUS, COLUMN_PRESSURE_BONUS
)
from engine.battle_log import to_dm_payload, to_image_prompt
from data.cards import CARD_REGISTRY


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_instance(card_id: str, owner: Player, level: int = 1) -> CardInstance:
    defn = CARD_REGISTRY[card_id]
    return CardInstance(
        instance_id=str(uuid.uuid4()),
        definition=defn,
        owner=owner,
        level=level,
    )


def make_board_card(instance: CardInstance, col: int, row: Row, face_down=False) -> BoardCard:
    return BoardCard(
        instance=instance,
        current_hp=instance.max_defense,
        col=col,
        row=row,
        owner=instance.owner,
        face_down=face_down,
    )


def fresh_state() -> GameState:
    state = GameState()
    state.player1.mana = 8
    state.player2.mana = 8
    return state


def place_card(state: GameState, instance: CardInstance, col: int, row: Row):
    """Directly place a card on the board (bypassing placement phase for tests)."""
    bc = make_board_card(instance, col, row)
    state.board.place(bc)
    return bc


# ---------------------------------------------------------------------------
# Test 1: Type advantage multipliers
# ---------------------------------------------------------------------------

def test_type_advantages():
    print("\n=== Test 1: Type Advantage Multipliers ===")
    cases = [
        (CardType.SPECTER, CardType.BEHEMOTH, 1.5, "Specter beats Behemoth"),
        (CardType.SPECTER, CardType.REVENANT, 0.75, "Specter weak to Revenant"),
        (CardType.REVENANT, CardType.SPECTER, 1.5, "Revenant beats Specter"),
        (CardType.REVENANT, CardType.PHANTOM, 0.75, "Revenant weak to Phantom"),
        (CardType.PHANTOM, CardType.REVENANT, 1.5, "Phantom beats Revenant"),
        (CardType.PHANTOM, CardType.BEHEMOTH, 0.75, "Phantom weak to Behemoth"),
        (CardType.BEHEMOTH, CardType.PHANTOM, 1.5, "Behemoth beats Phantom"),
        (CardType.BEHEMOTH, CardType.SPECTER, 0.75, "Behemoth weak to Specter"),
        (CardType.SPECTER, CardType.SPECTER, 1.0, "Neutral matchup"),
    ]
    for attacker_type, defender_type, expected, label in cases:
        actual = TYPE_MATCHUP[attacker_type][defender_type]
        status = "✅" if actual == expected else "❌"
        print(f"  {status} {label}: {actual} (expected {expected})")
    print()


# ---------------------------------------------------------------------------
# Test 2: Basic combat — Specter vs Behemoth (type advantage)
# ---------------------------------------------------------------------------

def test_basic_combat_type_advantage():
    print("=== Test 2: Basic Combat — Type Advantage ===")
    state = fresh_state()

    # Morthex (Specter, ATK=6) vs Bonecrag (Behemoth, DEF=14)
    morthex = make_instance("spec_001", Player.ONE)
    bonecrag = make_instance("beh_002", Player.TWO)

    place_card(state, morthex, col=1, row=Row.FRONT)
    place_card(state, bonecrag, col=1, row=Row.FRONT)

    state, result = phase_resolve(state)

    # Specter has advantage: damage = (6 base + 1 column_pressure) * 1.5 = 10
    specter_event = next(e for e in result.events if e.attacker_name == "Morthex the Hollow")
    expected_damage = int((6 + COLUMN_PRESSURE_BONUS) * 1.5)  # = 10
    status = "✅" if specter_event.damage_dealt == expected_damage else "❌"
    print(f"  {status} Specter→Behemoth damage: {specter_event.damage_dealt} (expected {expected_damage})")

    # Behemoth has disadvantage: damage = 9 * 0.75 = 6
    behemoth_event = next(e for e in result.events if e.attacker_name == "Bonecrag")
    expected_b_damage = int(9 * 0.75)  # = 6
    status = "✅" if behemoth_event.damage_dealt == expected_b_damage else "❌"
    print(f"  {status} Behemoth→Specter damage: {behemoth_event.damage_dealt} (expected {expected_b_damage})")
    print()


# ---------------------------------------------------------------------------
# Test 3: Speed ordering — faster card attacks first
# ---------------------------------------------------------------------------

def test_speed_ordering():
    print("=== Test 3: Speed Ordering ===")
    state = fresh_state()

    # Veyra (speed=10) vs Gravaul (speed=3)
    veyra = make_instance("spec_002", Player.ONE)
    gravaul = make_instance("rev_001", Player.TWO)

    place_card(state, veyra, col=0, row=Row.FRONT)
    place_card(state, gravaul, col=0, row=Row.FRONT)

    state, result = phase_resolve(state)

    first_event = result.events[0]
    status = "✅" if first_event.attacker_name == "Veyra Silentblade" else "❌"
    print(f"  {status} First attacker is fastest card: {first_event.attacker_name}")
    print()


# ---------------------------------------------------------------------------
# Test 4: Back row protection
# ---------------------------------------------------------------------------

def test_back_row_protection():
    print("=== Test 4: Back Row Protection ===")
    state = fresh_state()

    # P1: front row has Morthex in col 0
    # P2: front row has blocker in col 0, back row has Vorath in col 0
    # Morthex should NOT be able to target Vorath (blocker is in the way)

    morthex = make_instance("spec_001", Player.ONE)
    duskwarden = make_instance("rev_003", Player.TWO)   # front row blocker
    vorath = make_instance("beh_001", Player.TWO)       # back row, protected

    place_card(state, morthex, col=0, row=Row.FRONT)
    place_card(state, duskwarden, col=0, row=Row.FRONT)
    place_card(state, vorath, col=0, row=Row.BACK)

    state, result = phase_resolve(state)

    # Morthex should have attacked Duskwarden, not Vorath
    morthex_event = next((e for e in result.events if e.attacker_name == "Morthex the Hollow"), None)
    if morthex_event:
        status = "✅" if morthex_event.defender_name == "Duskwarden" else "❌"
        print(f"  {status} Morthex targeted front row blocker: {morthex_event.defender_name}")
    else:
        print("  ❌ Morthex event not found")
    print()


# ---------------------------------------------------------------------------
# Test 5: Flanking bonus
# ---------------------------------------------------------------------------

def test_flanking_bonus():
    print("=== Test 5: Flanking Bonus ===")
    state = fresh_state()

    # P1 occupies 3 front row columns (0, 1, 2)
    # P2 occupies only 1 front row column (1)
    # P1 front row cards should get +2 attack

    for col in [0, 1, 2]:
        inst = make_instance("spec_003", Player.ONE)  # Ashling, ATK=5
        place_card(state, inst, col=col, row=Row.FRONT)

    gravaul = make_instance("rev_001", Player.TWO)
    place_card(state, gravaul, col=1, row=Row.FRONT)

    state, result = phase_resolve(state)

    # P1 cards should have flanking applied
    p1_events = [e for e in result.events if e.attacker_owner == Player.ONE]
    has_bonus = any(e.position_bonus > 0 for e in p1_events)
    status = "✅" if has_bonus else "❌"
    print(f"  {status} Flanking bonus applied to P1 front row: {has_bonus}")
    print(f"  {status} Flanking player recorded: {result.flanking_applied}")
    print()


# ---------------------------------------------------------------------------
# Test 6: Mana validation
# ---------------------------------------------------------------------------

def test_mana_validation():
    print("=== Test 6: Mana Validation ===")
    state = GameState()
    state.player1.mana = 3

    vorath = make_instance("beh_001", Player.ONE)   # costs 7 mana
    state.player1.hand = [vorath]

    # Should fail — not enough mana, no Veil Surge capacity
    valid, msg = validate_placement(
        state, Player.ONE,
        [{"card_instance_id": vorath.instance_id, "col": 0, "row": Row.FRONT}]
    )
    status = "✅" if not valid else "❌"
    print(f"  {status} Correctly rejected over-budget placement: '{msg}'")

    # Now give enough mana
    state.player1.mana = 7
    valid, msg = validate_placement(
        state, Player.ONE,
        [{"card_instance_id": vorath.instance_id, "col": 0, "row": Row.FRONT}]
    )
    status = "✅" if valid else "❌"
    print(f"  {status} Correctly accepted valid placement")
    print()


# ---------------------------------------------------------------------------
# Test 7: Win condition — match scoring
# ---------------------------------------------------------------------------

def test_win_condition():
    print("=== Test 7: Win Condition — Match Scoring ===")
    state = GameState()
    state.player1.score = 2
    state.player2.score = 0
    state.current_round = 3

    # P1 has strong card, P2 has nothing
    morthex = make_instance("spec_001", Player.ONE)
    place_card(state, morthex, col=0, row=Row.FRONT)

    state, result = phase_resolve(state)

    # P1 should win with score 4 (2 existing + 2 for wipe)
    status = "✅" if result.match_winner == Player.ONE else "❌"
    print(f"  {status} P1 wins match after reaching score threshold: winner={result.match_winner}")
    print(f"  Score: P1={result.match_score['player_1']}, P2={result.match_score['player_2']}")
    print()


# ---------------------------------------------------------------------------
# Test 8: BattleLog serialization
# ---------------------------------------------------------------------------

def test_battle_log_serialization():
    print("=== Test 8: BattleLog DM Payload ===")
    state = fresh_state()

    morthex = make_instance("spec_001", Player.ONE)
    bonecrag = make_instance("beh_002", Player.TWO)
    place_card(state, morthex, col=0, row=Row.FRONT)
    place_card(state, bonecrag, col=0, row=Row.FRONT)

    state, result = phase_resolve(state)
    payload = to_dm_payload(result, "Lyra", "Kael")
    image_prompt = to_image_prompt(result, "Lyra", "Kael")

    status = "✅" if "combat_events" in payload else "❌"
    print(f"  {status} Payload has combat_events: {len(payload['combat_events'])} events")

    status = "✅" if "instructions" in payload else "❌"
    print(f"  {status} Payload has DM instructions")

    status = "✅" if len(image_prompt) > 20 else "❌"
    print(f"  {status} Image prompt generated: '{image_prompt[:80]}...'")

    status = "✅" if payload["round_outcome"]["winner"] in ["Lyra", "Kael", "Tie"] else "❌"
    print(f"  {status} Winner field uses player names: '{payload['round_outcome']['winner']}'")
    print()


# ---------------------------------------------------------------------------
# Test 9: Full round lifecycle
# ---------------------------------------------------------------------------

def test_full_round_lifecycle():
    print("=== Test 9: Full Round Lifecycle ===")
    state = GameState()

    # Load decks
    state.player1.deck = [
        make_instance("spec_001", Player.ONE),
        make_instance("spec_002", Player.ONE),
        make_instance("rev_002", Player.ONE),
    ]
    state.player2.deck = [
        make_instance("beh_002", Player.TWO),
        make_instance("phan_001", Player.TWO),
        make_instance("rev_001", Player.TWO),
    ]

    # Draw
    state = phase_draw(state)
    status = "✅" if len(state.player1.hand) == 3 else "❌"
    print(f"  {status} P1 drew cards: {len(state.player1.hand)}")

    # Mana
    state = phase_mana(state)
    status = "✅" if state.player1.mana == 4 else "❌"
    print(f"  {status} Mana incremented to: {state.player1.mana}")

    # Placement
    p1_card = state.player1.hand[0]
    p2_card = state.player2.hand[0]
    state.player1.mana = 8
    state.player2.mana = 8

    state = apply_placement(state, Player.ONE, [
        {"card_instance_id": p1_card.instance_id, "col": 1, "row": Row.FRONT}
    ])
    state = apply_placement(state, Player.TWO, [
        {"card_instance_id": p2_card.instance_id, "col": 1, "row": Row.FRONT}
    ])

    # Reveal
    state = phase_reveal(state)
    face_down_count = sum(1 for c in state.board.all_cards() if c.face_down)
    status = "✅" if face_down_count == 0 else "❌"
    print(f"  {status} All cards revealed (face_down=False): {face_down_count} still face down")

    # Resolve
    state, result = phase_resolve(state)
    status = "✅" if len(result.events) > 0 else "❌"
    print(f"  {status} Combat resolved: {len(result.events)} events")

    # Cleanup
    state = phase_cleanup(state)
    status = "✅" if state.current_round == 2 else "❌"
    print(f"  {status} Round advanced to: {state.current_round}")
    print()


# ---------------------------------------------------------------------------
# Test 10: Veil Surge (overdraft mana)
# ---------------------------------------------------------------------------

def test_veil_surge():
    print("=== Test 10: Veil Surge (Mana Overdraft) ===")
    state = GameState()
    state.player1.mana = 3

    vorath = make_instance("beh_001", Player.ONE)  # costs 7 — overdraft 4 (exceeds limit of 3)
    bonecrag = make_instance("beh_002", Player.ONE) # costs 5 — overdraft 2

    state.player1.hand = [vorath, bonecrag]

    # Bonecrag (cost 5) with 3 mana = overdraft 2, within VEIL_SURGE_MAX=3
    valid, msg = validate_placement(
        state, Player.ONE,
        [{"card_instance_id": bonecrag.instance_id, "col": 0, "row": Row.FRONT}]
    )
    status = "✅" if valid else "❌"
    print(f"  {status} Veil Surge within limit (overdraft 2) accepted: valid={valid}")

    # Vorath (cost 7) with 3 mana = overdraft 4, exceeds VEIL_SURGE_MAX=3
    valid, msg = validate_placement(
        state, Player.ONE,
        [{"card_instance_id": vorath.instance_id, "col": 0, "row": Row.FRONT}]
    )
    status = "✅" if not valid else "❌"
    print(f"  {status} Veil Surge over limit (overdraft 4) rejected: '{msg}'")
    print()


# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("🌑 Veilborn Rules Engine — Test Suite")
    print("=" * 50)

    test_type_advantages()
    test_basic_combat_type_advantage()
    test_speed_ordering()
    test_back_row_protection()
    test_flanking_bonus()
    test_mana_validation()
    test_win_condition()
    test_battle_log_serialization()
    test_full_round_lifecycle()
    test_veil_surge()

    print("=" * 50)
    print("✅ Test suite complete")
