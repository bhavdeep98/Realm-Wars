"""
Veilborn — DM Agent
Wraps the Claude API. Receives a BattleLog payload, returns structured narration.

CONTRACT: The DM agent is a storyteller, NOT a game arbiter.
- It reads outcomes from the BattleLog
- It narrates them dramatically
- It never changes winners, damage values, or any game state
- GameState is never passed to this module
"""

from __future__ import annotations
import json
import os
from dataclasses import dataclass
from typing import Optional
from openai import OpenAI
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# ---------------------------------------------------------------------------
# DM System Prompt — the voice and rules of the narrator
# ---------------------------------------------------------------------------

DM_SYSTEM_PROMPT = """You are the Veilborn Dungeon Master — the eternal voice of the Rift, the thinning place between the world of the living and the realm of ancient, hungry entities.

Your role is to narrate battles between Veilweavers — dark sorcerers who summon creatures from both sides of the Veil to crush their rivals. You are dramatic, evocative, and mythological in tone. You speak with authority and dark grandeur.

## Your Cardinal Rules

1. **Never alter outcomes.** The game engine has already decided every result — damage values, who is destroyed, who wins the round, the final score. You narrate what happened. You do not invent events or change results.

2. **Narrate events in order.** The `combat_events` array is sorted by `order`. Walk through them sequentially. Each event is a beat in the story.

3. **Make type advantages feel meaningful.** If a Specter strikes a Behemoth with advantage, describe why — the ghost slipping through armor, finding the Behemoth's vulnerable ancient flesh. If a card strikes at disadvantage, show the struggle.

4. **Acknowledge position and ability effects.** If flanking occurred, describe the encirclement. If a card used Lifesteal, describe the vitality drain. If Veil Echo triggered on death, make it feel catastrophic.

5. **Address both Veilweavers directly** by name. Make them feel present, like players at a table with a great storyteller.

6. **End every round with the score**, delivered dramatically, not mechanically.

7. **Veil Collapse (Round 5):** If `veil_collapse` is true, open with the Veil itself tearing apart — reality unraveling, power surging through all entities. This is the final cataclysmic round.

8. **Match winner:** If `match_winner` is set, deliver a proper conclusion. The loser's Veilweaver is defeated. Their entities dissolve back into the Veil. The winner's power is acknowledged.

## The Four Types — Their Voice

- **Specter:** Ghost-quick, surgical, evasive. They move like smoke, strike like cold iron. Use words like: tendrils, hollow, silent, slipping, shadow-step.
- **Revenant:** Undead, armored, relentless. They absorb punishment and keep marching. Use words like: unyielding, grave-fire, inexorable, deathless, siege.
- **Phantom:** Illusory, maddening, unpredictable. They reflect, trick, shift. Use words like: mirror, shimmering, echo, unreal, fracture.
- **Behemoth:** Ancient, monstrous, vast. They are geological in their destruction. Use words like: consuming, primordial, crushing, hunger, bone-protrusion.

## Output Format

Return a JSON object with exactly these fields:

```json
{
  "narration": "string — the full dramatic battle narration, 150-250 words",
  "round_title": "string — a short evocative title for this round (3-6 words, e.g. 'The Hollow Makes Its Move')",
  "key_moment": "string — one sentence identifying the single most dramatic moment of the round",
  "tone": "string — one of: 'tense', 'devastating', 'triumphant', 'chaotic', 'grim'"
}
```

Return only valid JSON. No preamble, no markdown fences.
"""

# ---------------------------------------------------------------------------
# Structured response
# ---------------------------------------------------------------------------

@dataclass
class DMNarration:
    narration: str
    round_title: str
    key_moment: str
    tone: str
    raw_payload: dict   # The BattleLog that produced this narration

    def display(self):
        """Pretty-print for testing and debugging."""
        divider = "─" * 60
        print(f"\n{divider}")
        print(f"⚔  {self.round_title.upper()}")
        print(f"{divider}")
        print(f"\n{self.narration}\n")
        print(f"📍 Key Moment: {self.key_moment}")
        print(f"🎭 Tone: {self.tone}")
        print(divider)


# ---------------------------------------------------------------------------
# DM Agent caller
# ---------------------------------------------------------------------------

def narrate_round(
    dm_payload: dict,
    api_key: Optional[str] = None,
    model: str = "gpt-4o",
) -> DMNarration:
    """
    Call the DM agent with a BattleLog payload.
    Returns a structured DMNarration.

    Args:
        dm_payload: The dict produced by battle_log.to_dm_payload()
        api_key: OpenAI API key. Falls back to OPENAI_API_KEY env var.
        model: OpenAI model to use.
    """
    client = OpenAI(
        api_key=api_key or os.environ.get("OPENAI_API_KEY")
    )

    # Strip the instructions field — that was for the old inline approach
    # The system prompt now carries all instructions
    payload_for_dm = {k: v for k, v in dm_payload.items() if k != "instructions"}

    user_message = f"""Narrate this Veilborn battle round:

{json.dumps(payload_for_dm, indent=2)}"""

    response = client.chat.completions.create(
        model=model,
        max_tokens=1024,
        response_format={"type": "json_object"},
        messages=[
            {"role": "system", "content": DM_SYSTEM_PROMPT},
            {"role": "user", "content": user_message}
        ]
    )

    raw_text = response.choices[0].message.content.strip()

    # Parse JSON response
    try:
        parsed = json.loads(raw_text)
    except json.JSONDecodeError:
        # Fallback: try to extract JSON if wrapped in backticks
        import re
        match = re.search(r'\{.*\}', raw_text, re.DOTALL)
        if match:
            parsed = json.loads(match.group())
        else:
            raise ValueError(f"DM agent returned unparseable response:\n{raw_text}")

    return DMNarration(
        narration=parsed["narration"],
        round_title=parsed["round_title"],
        key_moment=parsed["key_moment"],
        tone=parsed["tone"],
        raw_payload=dm_payload,
    )


# ---------------------------------------------------------------------------
# Match-level narrator — narrates all rounds sequentially
# ---------------------------------------------------------------------------

def narrate_match(
    round_payloads: list[dict],
    p1_name: str = "Player 1",
    p2_name: str = "Player 2",
    api_key: Optional[str] = None,
) -> list[DMNarration]:
    """
    Narrate all rounds of a match in sequence.
    Returns a list of DMNarration objects, one per round.
    """
    narrations = []
    print(f"\n🌑 VEILBORN MATCH: {p1_name} vs {p2_name}")
    print("=" * 60)

    for i, payload in enumerate(round_payloads):
        print(f"\n⏳ Narrating Round {i + 1}...", end="", flush=True)
        narration = narrate_round(payload, api_key=api_key)
        narration.display()
        narrations.append(narration)

        # Stop if match is over
        if payload.get("match_winner"):
            break

    return narrations
