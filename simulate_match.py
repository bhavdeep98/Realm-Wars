"""
Veilborn — Match Simulator
Runs a complete simulated match between two AI-controlled players,
pipes each round through the DM agent, and generates image prompts.

Usage:
    python simulate_match.py                        # uses OPENAI_API_KEY env var
    python simulate_match.py --dry-run              # skip API calls, show structure only
    python simulate_match.py --rounds 3             # play only 3 rounds
"""

from __future__ import annotations
import sys
import os
import json
import random
import argparse
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from engine.models import (
    GameState, Player, Row, PlayerState, CardInstance, GamePhase
)
from engine.rules import (
    phase_draw, phase_mana, apply_placement,
    phase_reveal, phase_resolve, phase_cleanup
)
from engine.battle_log import to_dm_payload, to_image_prompt
from engine.dm_agent import narrate_round, DMNarration
from engine.image_agent import build_battle_scene_prompt, build_card_art_prompt
from data.cards import CARD_REGISTRY, STARTER_CARDS


# ---------------------------------------------------------------------------
# AI Player — makes simple strategic decisions for simulation
# ---------------------------------------------------------------------------

class AIPlayer:
    """
    A simple AI player that makes legal placement decisions.
    Strategy: place highest-attack cards in front row, spread columns.
    This is intentionally beatable — it's for simulation, not competition.
    """

    def __init__(self, player: Player, strategy: str = "aggressive"):
        self.player = player
        self.strategy = strategy  # 'aggressive' | 'defensive' | 'spread'

    def choose_placements(self, state: GameState, max_cards: int = 3) -> list[dict]:
        ps = state.get_player_state(self.player)
        available = [c for c in ps.hand if not c.is_dormant]
        if not available:
            return []

        # Sort by strategy
        if self.strategy == "aggressive":
            available.sort(key=lambda c: c.definition.base_attack, reverse=True)
        elif self.strategy == "defensive":
            available.sort(key=lambda c: c.max_defense, reverse=True)
        else:  # spread — balance attack and defense
            available.sort(key=lambda c: c.definition.base_attack + c.instance.max_defense, reverse=True)

        placements = []
        used_cols = set()
        mana_remaining = ps.mana

        for card in available:
            if len(placements) >= max_cards:
                break
            if card.definition.mana_cost > mana_remaining:
                continue

            # Pick a column not yet used, prefer center columns
            col_priority = [1, 2, 0, 3]
            chosen_col = None
            for col in col_priority:
                if col not in used_cols:
                    # Check cell is empty
                    existing = state.board.get(col, Row.FRONT, self.player)
                    if existing is None:
                        chosen_col = col
                        break

            if chosen_col is None:
                # Try back row
                for col in col_priority:
                    if col not in used_cols:
                        existing = state.board.get(col, Row.BACK, self.player)
                        if existing is None:
                            chosen_col = col
                            break

            if chosen_col is None:
                continue

            # Defensive player puts high-defense cards in back row
            row = Row.BACK if (
                self.strategy == "defensive" and
                card.max_defense > 12 and
                len(placements) > 0
            ) else Row.FRONT

            placements.append({
                "card_instance_id": card.instance_id,
                "col": chosen_col,
                "row": row,
            })
            used_cols.add(chosen_col)
            mana_remaining -= card.definition.mana_cost

        return placements


# ---------------------------------------------------------------------------
# Deck builder — creates a starting deck from the card registry
# ---------------------------------------------------------------------------

def build_starter_deck(player: Player, strategy: str = "balanced") -> list[CardInstance]:
    """Build a 10-card starting deck for a player."""
    all_cards = list(STARTER_CARDS)

    if strategy == "specter_rush":
        # Heavy on Specters with some Behemoths
        picks = ["spec_001", "spec_002", "spec_003", "spec_001", "spec_002",
                 "beh_002", "beh_003", "rev_002", "phan_002", "spec_003"]
    elif strategy == "behemoth_wall":
        # Slow, heavy Behemoths backed by Revenants
        picks = ["beh_001", "beh_002", "beh_003", "beh_002", "rev_001",
                 "rev_003", "rev_002", "rev_001", "phan_001", "beh_003"]
    else:  # balanced
        picks = ["spec_001", "rev_001", "phan_001", "beh_002",
                 "spec_002", "rev_002", "phan_002", "beh_003",
                 "spec_003", "rev_003"]

    deck = []
    for card_id in picks:
        defn = CARD_REGISTRY[card_id]
        instance = CardInstance(
            instance_id=str(uuid.uuid4()),
            definition=defn,
            owner=player,
            level=1,
            xp=0,
        )
        deck.append(instance)

    random.shuffle(deck)
    return deck


# ---------------------------------------------------------------------------
# Match Simulator
# ---------------------------------------------------------------------------

def simulate_match(
    p1_name: str = "Lyra the Forsaken",
    p2_name: str = "Kael Duskmantle",
    p1_strategy: str = "specter_rush",
    p2_strategy: str = "behemoth_wall",
    dry_run: bool = False,
    max_rounds: int = 5,
    api_key: Optional[str] = None,
) -> dict:
    """
    Run a complete simulated match.
    Returns a dict with all round payloads, narrations, and image prompts.
    """
    from typing import Optional

    print(f"\n{'=' * 60}")
    print(f"  🌑 VEILBORN — THE RIFT OPENS")
    print(f"  {p1_name} vs {p2_name}")
    print(f"  Strategies: {p1_strategy} vs {p2_strategy}")
    print(f"{'=' * 60}")

    # Initialize game state
    state = GameState()
    state.player1 = PlayerState(Player.ONE)
    state.player2 = PlayerState(Player.TWO)
    state.player1.deck = build_starter_deck(Player.ONE, p1_strategy)
    state.player2.deck = build_starter_deck(Player.TWO, p2_strategy)

    ai1 = AIPlayer(Player.ONE, strategy="aggressive" if "specter" in p1_strategy else "defensive")
    ai2 = AIPlayer(Player.TWO, strategy="defensive" if "behemoth" in p2_strategy else "spread")

    match_results = {
        "game_id": state.game_id,
        "p1_name": p1_name,
        "p2_name": p2_name,
        "rounds": [],
        "narrations": [],
        "image_prompts": [],
        "match_winner": None,
    }

    for round_num in range(1, max_rounds + 1):
        if state.match_winner:
            break

        print(f"\n{'─' * 60}")
        print(f"  ROUND {round_num}")
        print(f"  Score: {p1_name} {state.player1.score} — {state.player2.score} {p2_name}")
        print(f"{'─' * 60}")

        # Phase: Draw
        state = phase_draw(state)
        print(f"  ✋ P1 hand: {len(state.player1.hand)} cards | P2 hand: {len(state.player2.hand)} cards")

        # Phase: Mana
        state = phase_mana(state)
        print(f"  ⚡ P1 mana: {state.player1.mana} | P2 mana: {state.player2.mana}")

        # Phase: Placement (AI decisions)
        p1_placements = ai1.choose_placements(state)
        p2_placements = ai2.choose_placements(state)

        if p1_placements:
            state = apply_placement(state, Player.ONE, p1_placements)
        if p2_placements:
            state = apply_placement(state, Player.TWO, p2_placements)

        p1_placed = len(p1_placements)
        p2_placed = len(p2_placements)
        print(f"  🃏 P1 placed: {p1_placed} cards | P2 placed: {p2_placed} cards")

        if p1_placed == 0 and p2_placed == 0:
            print("  ⚠️  No cards placed this round — skipping")
            state.current_round += 1
            continue

        # Phase: Reveal
        state = phase_reveal(state)

        # Phase: Resolve
        state, result = phase_resolve(state)

        # Build payloads
        dm_payload = to_dm_payload(result, p1_name, p2_name)
        img_prompt = build_battle_scene_prompt(result)

        match_results["rounds"].append(dm_payload)
        match_results["image_prompts"].append({
            "round": round_num,
            "positive": img_prompt.positive,
            "negative": img_prompt.negative,
            "subject": img_prompt.subject,
        })

        # Show round summary
        winner_label = p1_name if result.round_winner == Player.ONE else (
            p2_name if result.round_winner == Player.TWO else "TIE"
        )
        print(f"  ⚔  Combat: {len(result.events)} events | Round winner: {winner_label}")
        print(f"  📊 Match score: {p1_name} {result.match_score['player_1']} — {result.match_score['player_2']} {p2_name}")

        # DM Narration
        if not dry_run:
            print(f"\n  🎭 Requesting DM narration...", end="", flush=True)
            try:
                narration = narrate_round(dm_payload, api_key=api_key)
                match_results["narrations"].append({
                    "round": round_num,
                    "title": narration.round_title,
                    "narration": narration.narration,
                    "key_moment": narration.key_moment,
                    "tone": narration.tone,
                })
                narration.display()
            except Exception as e:
                print(f"\n  ⚠️  DM narration failed: {e}")
                match_results["narrations"].append({"round": round_num, "error": str(e)})
        else:
            print(f"\n  [dry-run] Skipping DM narration")
            print(f"  📜 BattleLog payload:")
            print(json.dumps(dm_payload, indent=4, default=str))
            print(f"\n  🎨 Image prompt:")
            img_prompt.display()

        # Phase: Cleanup
        if not state.match_winner:
            state = phase_cleanup(state)

    # Match over
    match_results["match_winner"] = (
        p1_name if state.match_winner == Player.ONE else
        p2_name if state.match_winner == Player.TWO else
        "Draw"
    )

    print(f"\n{'=' * 60}")
    print(f"  🏆 MATCH OVER")
    print(f"  Winner: {match_results['match_winner']}")
    print(f"  Final score: {p1_name} {state.player1.score} — {state.player2.score} {p2_name}")
    print(f"{'=' * 60}\n")

    return match_results


# ---------------------------------------------------------------------------
# Card art preview — show what card art prompts look like
# ---------------------------------------------------------------------------

def preview_card_art_prompts():
    """Show what card art prompts look like for all starter cards."""
    from engine.image_agent import build_card_art_prompt
    print("\n🎨 CARD ART PROMPT PREVIEW")
    print("=" * 60)
    for card in STARTER_CARDS:
        prompt = build_card_art_prompt(card)
        print(f"\n[{card.rarity.value}] {card.name} ({card.card_type.value})")
        print(f"  → {prompt.positive[:140]}...")


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Veilborn Match Simulator")
    parser.add_argument("--dry-run", action="store_true",
                        help="Skip API calls, show BattleLog payloads instead")
    parser.add_argument("--rounds", type=int, default=5,
                        help="Maximum rounds to simulate (default: 5)")
    parser.add_argument("--p1", default="Lyra the Forsaken",
                        help="Player 1 name")
    parser.add_argument("--p2", default="Kael Duskmantle",
                        help="Player 2 name")
    parser.add_argument("--p1-strategy", default="specter_rush",
                        choices=["specter_rush", "behemoth_wall", "balanced"])
    parser.add_argument("--p2-strategy", default="behemoth_wall",
                        choices=["specter_rush", "behemoth_wall", "balanced"])
    parser.add_argument("--card-art-preview", action="store_true",
                        help="Preview card art prompts for all starter cards")

    args = parser.parse_args()

    if args.card_art_preview:
        preview_card_art_prompts()
        sys.exit(0)

    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key and not args.dry_run:
        print("⚠️  No OPENAI_API_KEY found. Running in dry-run mode.")
        args.dry_run = True

    results = simulate_match(
        p1_name=args.p1,
        p2_name=args.p2,
        p1_strategy=args.p1_strategy,
        p2_strategy=args.p2_strategy,
        dry_run=args.dry_run,
        max_rounds=args.rounds,
        api_key=api_key,
    )

    # Save results to file
    output_file = f"match_{results['game_id'][:8]}.json"
    with open(output_file, "w") as f:
        json.dump(results, f, indent=2, default=str)
    print(f"📁 Match results saved to: {output_file}")
