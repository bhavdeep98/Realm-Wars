"""
Veilborn Rules Engine — BattleLog Serializer
Converts a RoundResult into a clean JSON payload for the DM agent.
The DM agent reads this and ONLY this. It never touches GameState.
"""

from __future__ import annotations
import json
from .models import RoundResult, Player


def to_dm_payload(result: RoundResult, p1_name: str = "Player 1", p2_name: str = "Player 2") -> dict:
    """
    Serialize a RoundResult into the DM agent's input payload.
    Every field the DM needs is here. Nothing more.
    """
    def player_label(p: Player) -> str:
        return p1_name if p == Player.ONE else p2_name

    events_payload = []
    for e in result.events:
        event_dict = {
            "order": e.order,
            "attacker": {
                "name": e.attacker_name,
                "type": e.attacker_type,
                "level": e.attacker_level,
                "owner": player_label(e.attacker_owner),
            },
            "defender": {
                "name": e.defender_name,
                "type": e.defender_type,
                "level": e.defender_level,
                "owner": player_label(e.defender_owner),
            },
            "type_advantage": _advantage_label(e.type_multiplier),
            "damage_dealt": e.damage_dealt,
            "position_bonus": e.position_bonus,
            "defender_destroyed": e.defender_destroyed,
        }
        if e.ability_triggered:
            event_dict["ability"] = {
                "name": e.ability_triggered,
                "description": e.ability_effect_description,
            }
        events_payload.append(event_dict)

    payload = {
        "round": result.round_number,
        "veil_collapse": result.veil_collapse,
        "flanking_bonus_awarded_to": player_label(result.flanking_applied) if result.flanking_applied else None,
        "combat_events": events_payload,
        "round_outcome": {
            "p1_surviving_defense": result.p1_surviving_defense,
            "p2_surviving_defense": result.p2_surviving_defense,
            "winner": player_label(result.round_winner) if result.round_winner else "Tie",
            "points_awarded": result.round_points_awarded,
            "reason": _outcome_reason(result, p1_name, p2_name),
        },
        "match_score": {
            p1_name: result.match_score["player_1"],
            p2_name: result.match_score["player_2"],
        },
        "match_winner": player_label(result.match_winner) if result.match_winner else None,
        "instructions": (
            "You are the Veilborn Dungeon Master. Narrate this round dramatically and cinematically "
            "in 150-250 words. Narrate each combat event in order. Do not change any outcomes — "
            "the winner, damage dealt, and destroyed cards are fixed. Use dark mythological language "
            "befitting a world where the Veil between life and death is thinning. Address both "
            "Veilweavers directly. End with the round score. If match_winner is set, deliver a "
            "dramatic match conclusion."
        )
    }
    return payload


def to_image_prompt(result: RoundResult, p1_name: str = "Player 1", p2_name: str = "Player 2") -> str:
    """
    Generate an image prompt for the most dramatic moment of the round.
    Used by the image generation agent.
    """
    # Find the most impactful event (highest damage, or a destruction)
    if not result.events:
        return "A dark Veil rift crackling with dark energy, two shadowy figures facing each other"

    key_event = max(result.events, key=lambda e: (e.defender_destroyed, e.damage_dealt))

    type_visuals = {
        "Specter": "translucent ghostly assassin trailing shadow tendrils",
        "Revenant": "armored undead warrior wreathed in pale death-fire",
        "Phantom": "shimmering illusory figure shifting between forms",
        "Behemoth": "massive ancient flesh-horror with obsidian bone protrusions",
    }

    attacker_desc = type_visuals.get(key_event.attacker_type, "dark entity")
    defender_desc = type_visuals.get(key_event.defender_type, "shadowy creature")
    action = "destroying" if key_event.defender_destroyed else "striking"

    prompt = (
        f"Dark fantasy battle scene, {attacker_desc} named {key_event.attacker_name} "
        f"{action} a {defender_desc} named {key_event.defender_name}, "
        f"set in a crumbling Veil rift where reality tears apart, "
        f"dark energy crackling, dramatic lighting, epic fantasy art style, "
        f"highly detailed, cinematic composition, dark mythology aesthetic"
    )
    return prompt


def _advantage_label(multiplier: float) -> str:
    if multiplier == 1.5:
        return "advantage (1.5x)"
    elif multiplier == 0.75:
        return "disadvantage (0.75x)"
    return "neutral (1.0x)"


def _outcome_reason(result: RoundResult, p1_name: str, p2_name: str) -> str:
    if result.round_winner is None:
        return "Both sides annihilated each other completely — a mutual destruction"
    winner_def = result.p1_surviving_defense if result.round_winner == Player.ONE else result.p2_surviving_defense
    loser_def = result.p2_surviving_defense if result.round_winner == Player.ONE else result.p1_surviving_defense
    winner_name = p1_name if result.round_winner == Player.ONE else p2_name
    if loser_def == 0:
        return f"{winner_name} achieved a full wipe — all enemy cards destroyed (+2 points)"
    return f"{winner_name} had higher surviving defense ({winner_def} vs {loser_def}) (+1 point)"
