"""
Veilborn — Starter Card Definitions
12 cards across 4 types. Enough for a full test match.
"""

from engine.models import CardDefinition, CardType, Rarity, Ability, AbilityTrigger, AbilityEffect

STARTER_CARDS: list[CardDefinition] = [

    # ── SPECTERS ──────────────────────────────────────────────────────────
    CardDefinition(
        id="spec_001",
        name="Morthex the Hollow",
        card_type=CardType.SPECTER,
        rarity=Rarity.COMMON,
        base_attack=6,
        base_defense=8,
        speed=8,
        mana_cost=3,
        ability=Ability(
            trigger=AbilityTrigger.ON_ATTACK,
            effect=AbilityEffect.LIFESTEAL,
            value=0.3,
            description="Drains 30% of damage dealt as vitality"
        ),
        lore="Once a court assassin, Morthex slipped through the Veil mid-kill and never fully returned.",
    ),
    CardDefinition(
        id="spec_002",
        name="Veyra Silentblade",
        card_type=CardType.SPECTER,
        rarity=Rarity.RARE,
        base_attack=9,
        base_defense=6,
        speed=10,
        mana_cost=4,
        ability=Ability(
            trigger=AbilityTrigger.PASSIVE,
            effect=AbilityEffect.GHOST_STEP,
            value=1.0,
            description="Once per match, ignores back-row protection"
        ),
        lore="She moves through stone and steel alike. The Veil is simply another wall to her.",
    ),
    CardDefinition(
        id="spec_003",
        name="Ashling",
        card_type=CardType.SPECTER,
        rarity=Rarity.COMMON,
        base_attack=5,
        base_defense=5,
        speed=7,
        mana_cost=2,
        ability=None,
        lore="A child who wandered too close to the Veil. Now she wanders forever.",
    ),

    # ── REVENANTS ─────────────────────────────────────────────────────────
    CardDefinition(
        id="rev_001",
        name="Gravaul the Unyielding",
        card_type=CardType.REVENANT,
        rarity=Rarity.RARE,
        base_attack=7,
        base_defense=14,
        speed=3,
        mana_cost=4,
        ability=Ability(
            trigger=AbilityTrigger.PASSIVE,
            effect=AbilityEffect.ARMOR,
            value=2.0,
            description="Reduces all incoming damage by 2"
        ),
        lore="Gravaul has died eleven times. He finds it less concerning each time.",
    ),
    CardDefinition(
        id="rev_002",
        name="Serath the Unburied",
        card_type=CardType.REVENANT,
        rarity=Rarity.COMMON,
        base_attack=8,
        base_defense=10,
        speed=4,
        mana_cost=3,
        ability=Ability(
            trigger=AbilityTrigger.ON_SURVIVE_ROUND,
            effect=AbilityEffect.LAST_STAND,
            value=3.0,
            description="Gains +3 attack when below 50% HP"
        ),
        lore="The more Serath bleeds, the more dangerous he becomes.",
    ),
    CardDefinition(
        id="rev_003",
        name="Duskwarden",
        card_type=CardType.REVENANT,
        rarity=Rarity.COMMON,
        base_attack=6,
        base_defense=12,
        speed=2,
        mana_cost=3,
        ability=None,
        lore="A sentinel of the Veil's edge. Patient, immovable, inevitable.",
    ),

    # ── PHANTOMS ──────────────────────────────────────────────────────────
    CardDefinition(
        id="phan_001",
        name="Mirrex",
        card_type=CardType.PHANTOM,
        rarity=Rarity.EPIC,
        base_attack=7,
        base_defense=7,
        speed=6,
        mana_cost=5,
        ability=Ability(
            trigger=AbilityTrigger.ON_ATTACK,
            effect=AbilityEffect.THORNS,
            value=0.5,
            description="Attacker takes 50% of damage dealt back as reflection"
        ),
        lore="Mirrex shows you your own destruction. Then makes it real.",
    ),
    CardDefinition(
        id="phan_002",
        name="The Lurking Shade",
        card_type=CardType.PHANTOM,
        rarity=Rarity.COMMON,
        base_attack=5,
        base_defense=6,
        speed=5,
        mana_cost=2,
        ability=None,
        lore="It has no name because it has no substance. It simply is, and then isn't.",
    ),
    CardDefinition(
        id="phan_003",
        name="Veilborn Trickster",
        card_type=CardType.PHANTOM,
        rarity=Rarity.RARE,
        base_attack=8,
        base_defense=5,
        speed=9,
        mana_cost=4,
        ability=Ability(
            trigger=AbilityTrigger.PASSIVE,
            effect=AbilityEffect.LAST_STAND,
            value=4.0,
            description="Gains +4 attack when below 50% HP"
        ),
        lore="The Trickster is most dangerous when cornered. Don't corner it.",
    ),

    # ── BEHEMOTHS ─────────────────────────────────────────────────────────
    CardDefinition(
        id="beh_001",
        name="Vorath the Consuming",
        card_type=CardType.BEHEMOTH,
        rarity=Rarity.LEGENDARY,
        base_attack=12,
        base_defense=18,
        speed=1,
        mana_cost=7,
        ability=Ability(
            trigger=AbilityTrigger.ON_DEATH,
            effect=AbilityEffect.VEIL_ECHO,
            value=0.5,
            description="On death, releases a death echo dealing half its attack to its killer"
        ),
        lore="When Vorath dies, the killing blow echoes back. Some victories aren't worth the price.",
    ),
    CardDefinition(
        id="beh_002",
        name="Bonecrag",
        card_type=CardType.BEHEMOTH,
        rarity=Rarity.COMMON,
        base_attack=9,
        base_defense=14,
        speed=2,
        mana_cost=5,
        ability=None,
        lore="A thing assembled from the bones of things that should not be.",
    ),
    CardDefinition(
        id="beh_003",
        name="The Pale Hunger",
        card_type=CardType.BEHEMOTH,
        rarity=Rarity.RARE,
        base_attack=10,
        base_defense=12,
        speed=3,
        mana_cost=6,
        ability=Ability(
            trigger=AbilityTrigger.ON_ATTACK,
            effect=AbilityEffect.LIFESTEAL,
            value=0.4,
            description="Feeds on the vitality of those it strikes, healing 40% of damage dealt"
        ),
        lore="It is always hungry. It will always be hungry. Feed it and it only grows.",
    ),
]

# Quick lookup by id
CARD_REGISTRY: dict[str, CardDefinition] = {c.id: c for c in STARTER_CARDS}
