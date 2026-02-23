"""
Veilborn — Image Agent
Builds rich, consistent image generation prompts from BattleLog data.
Designed to integrate with fal.ai or Replicate for actual generation.

Two modes:
  1. Battle Scene — the key moment of a round (generated async after narration)
  2. Card Art — generated once when a card is created, cached permanently

The image agent never touches GameState. It reads BattleLog and card definitions only.
"""

from __future__ import annotations
from dataclasses import dataclass
from typing import Optional
from .models import RoundResult, CardDefinition, CardType, Rarity


# ---------------------------------------------------------------------------
# Visual vocabulary — consistent style tokens per type
# ---------------------------------------------------------------------------

TYPE_VISUAL = {
    "Specter": {
        "form": "translucent ghostly assassin, semi-transparent ethereal body",
        "details": "trailing shadow tendrils, hollow void eyes, wisps of dark mist",
        "colors": "deep violet, cold silver, pitch black",
        "action_words": ["slipping through", "dissolving into", "materializing from", "striking from within"],
    },
    "Revenant": {
        "form": "armored undead warrior, ancient battle-worn plate mail",
        "details": "wreathed in pale death-fire, exposed bone at joints, glowing grave-light eyes",
        "colors": "bone white, rusted iron, pale green flame",
        "action_words": ["marching through", "absorbing", "bearing down on", "sieging"],
    },
    "Phantom": {
        "form": "shimmering illusory figure, constantly shifting between forms",
        "details": "mirror-like surface fracturing reality around it, multiple overlapping silhouettes",
        "colors": "iridescent silver, fractured prismatic light, deep indigo",
        "action_words": ["reflecting", "shattering the image of", "becoming", "unraveling"],
    },
    "Behemoth": {
        "form": "massive ancient flesh-horror, towering creature of primordial nightmare",
        "details": "obsidian bone protrusions, multiple eyes, consuming maw, geological scale",
        "colors": "dark crimson, obsidian black, deep earthy brown",
        "action_words": ["consuming", "crushing beneath", "devouring", "overwhelming"],
    },
}

RARITY_STYLE = {
    "Common": "detailed fantasy illustration",
    "Rare": "highly detailed fantasy art, dramatic lighting",
    "Epic": "masterpiece fantasy art, cinematic lighting, awe-inspiring",
    "Legendary": "legendary artwork, breathtaking composition, divine and terrible beauty",
}

# Consistent style suffix applied to all generated images
STYLE_SUFFIX = (
    "dark mythology aesthetic, Veil rift background with crackling dark energy, "
    "professional fantasy card game art, 4k resolution, dramatic shadows"
)

NEGATIVE_PROMPT = (
    "cartoon, anime, bright colors, cheerful, simple, low quality, blurry, "
    "watermark, text, UI elements, white background"
)


# ---------------------------------------------------------------------------
# Prompt dataclass
# ---------------------------------------------------------------------------

@dataclass
class ImagePrompt:
    positive: str
    negative: str
    subject: str        # What the image depicts (for logging/caching)
    prompt_type: str    # 'battle_scene' or 'card_art'

    def display(self):
        print(f"\n🎨 Image Prompt ({self.prompt_type})")
        print(f"   Subject: {self.subject}")
        print(f"   Positive: {self.positive[:120]}...")
        print(f"   Negative: {self.negative[:80]}...")


# ---------------------------------------------------------------------------
# Battle Scene Prompt
# ---------------------------------------------------------------------------

def build_battle_scene_prompt(result: RoundResult) -> ImagePrompt:
    """
    Build an image prompt for the most dramatic moment of a combat round.
    Called after phase_resolve(), runs async while DM narrates.
    """
    if not result.events:
        return ImagePrompt(
            positive=f"A dark Veil rift tearing open, crackling with ancient energy, two Veilweavers facing each other across a shattered battlefield, {STYLE_SUFFIX}",
            negative=NEGATIVE_PROMPT,
            subject="Empty rift opening",
            prompt_type="battle_scene",
        )

    # Find the key moment: prioritize destructions, then highest damage
    destructions = [e for e in result.events if e.defender_destroyed]
    key_event = (
        max(destructions, key=lambda e: e.damage_dealt)
        if destructions
        else max(result.events, key=lambda e: e.damage_dealt)
    )

    attacker_vis = TYPE_VISUAL.get(key_event.attacker_type, TYPE_VISUAL["Specter"])
    defender_vis = TYPE_VISUAL.get(key_event.defender_type, TYPE_VISUAL["Specter"])

    import random
    action = random.choice(attacker_vis["action_words"])

    # Build the scene description
    if key_event.defender_destroyed:
        scene = (
            f"{attacker_vis['form']} named {key_event.attacker_name}, "
            f"{attacker_vis['details']}, {action} and destroying "
            f"a {defender_vis['form']} named {key_event.defender_name}, "
            f"{defender_vis['details']}, "
            f"the defeated creature dissolving back into the Veil in an explosion of dark energy"
        )
        subject = f"{key_event.attacker_name} destroys {key_event.defender_name}"
    else:
        scene = (
            f"{attacker_vis['form']} named {key_event.attacker_name}, "
            f"{attacker_vis['details']}, {action} "
            f"a {defender_vis['form']} named {key_event.defender_name}, "
            f"{defender_vis['details']}, "
            f"both locked in titanic combat as the Veil cracks around them"
        )
        subject = f"{key_event.attacker_name} strikes {key_event.defender_name}"

    # Add ability flavor
    ability_flavor = ""
    if key_event.ability_triggered == "Lifesteal":
        ability_flavor = ", dark energy visibly flowing from the victim into the attacker"
    elif key_event.ability_triggered == "Veil Echo":
        ability_flavor = ", a ghostly echo of the destroyed creature lashing back at its killer"

    # Veil Collapse flavor
    collapse_flavor = ""
    if result.veil_collapse:
        collapse_flavor = ", the Veil itself tearing apart behind them, reality fracturing, ancient darkness pouring through"

    positive = f"{scene}{ability_flavor}{collapse_flavor}, {STYLE_SUFFIX}"

    return ImagePrompt(
        positive=positive,
        negative=NEGATIVE_PROMPT,
        subject=subject,
        prompt_type="battle_scene",
    )


# ---------------------------------------------------------------------------
# Card Art Prompt
# ---------------------------------------------------------------------------

def build_card_art_prompt(card: CardDefinition) -> ImagePrompt:
    """
    Build an image prompt for a card's portrait art.
    Called once when a card is first created. Art is cached permanently.
    """
    vis = TYPE_VISUAL.get(card.card_type.value, TYPE_VISUAL["Specter"])
    rarity_style = RARITY_STYLE.get(card.rarity.value, "detailed fantasy illustration")

    # Rarity-based framing
    if card.rarity == Rarity.LEGENDARY:
        framing = "full body portrait in an ornate frame, radiating terrible power, the embodiment of ancient myth"
    elif card.rarity == Rarity.EPIC:
        framing = "dramatic three-quarter portrait, powerful and imposing, surrounded by swirling dark energy"
    elif card.rarity == Rarity.RARE:
        framing = "detailed portrait with environmental storytelling, mid-action pose"
    else:
        framing = "character portrait, clear and iconic design"

    # Ability visual hint
    ability_visual = ""
    if card.ability:
        ability_visuals = {
            "lifesteal": ", dark tendrils of stolen life force trailing from its hands",
            "thorns": ", sharp crystalline spines erupting from its body",
            "last_stand": ", battle-scarred with glowing wounds that pulse with defiant energy",
            "ghost_step": ", one foot stepping through a wall as if it were smoke",
            "veil_echo": ", a ghostly mirror-image of itself hovering behind it",
            "armor": ", covered in impossibly thick plates of dark bone and iron",
        }
        ability_visual = ability_visuals.get(card.ability.effect.value, "")

    positive = (
        f"{rarity_style}, {vis['form']} named {card.name}, "
        f"{vis['details']}{ability_visual}, "
        f"color palette: {vis['colors']}, "
        f"{framing}, "
        f"dark fantasy card game portrait, Veilborn aesthetic, "
        f"{STYLE_SUFFIX}"
    )

    return ImagePrompt(
        positive=positive,
        negative=NEGATIVE_PROMPT,
        subject=f"Card art for {card.name} ({card.card_type.value}, {card.rarity.value})",
        prompt_type="card_art",
    )


# ---------------------------------------------------------------------------
# Integration stubs — swap these for real API calls
# ---------------------------------------------------------------------------

def generate_image_fal(prompt: ImagePrompt, output_path: Optional[str] = None) -> str:
    """
    Stub for fal.ai integration.
    Replace the body with actual fal.ai API call when ready.

    Returns: URL or local path of generated image.

    Real implementation:
        import fal_client
        result = fal_client.run(
            "fal-ai/flux/schnell",
            arguments={
                "prompt": prompt.positive,
                "negative_prompt": prompt.negative,
                "image_size": "portrait_4_3",
                "num_inference_steps": 4,
            }
        )
        return result["images"][0]["url"]
    """
    print(f"  [fal.ai stub] Would generate: {prompt.subject}")
    return f"https://placeholder.veilborn.io/{prompt.subject.replace(' ', '_')}.png"


def generate_image_replicate(prompt: ImagePrompt, output_path: Optional[str] = None) -> str:
    """
    Stub for Replicate integration.
    Replace with actual replicate API call when ready.

    Real implementation:
        import replicate
        output = replicate.run(
            "stability-ai/sdxl:latest",
            input={
                "prompt": prompt.positive,
                "negative_prompt": prompt.negative,
                "width": 768,
                "height": 1024,
            }
        )
        return output[0]
    """
    print(f"  [Replicate stub] Would generate: {prompt.subject}")
    return f"https://placeholder.veilborn.io/{prompt.subject.replace(' ', '_')}.png"


# Default generator — swap between fal/replicate here
generate_image = generate_image_fal
