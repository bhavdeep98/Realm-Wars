"""
Veilborn Rules Engine — Data Models
All game state is represented here. Pure data, no logic.
"""

from __future__ import annotations
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional
import uuid


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

class CardType(Enum):
    SPECTER = "Specter"      # Beats Behemoth, weak to Revenant
    REVENANT = "Revenant"    # Beats Specter, weak to Phantom
    PHANTOM = "Phantom"      # Beats Revenant, weak to Behemoth
    BEHEMOTH = "Behemoth"    # Beats Phantom, weak to Specter


class Rarity(Enum):
    COMMON = "Common"
    RARE = "Rare"
    EPIC = "Epic"
    LEGENDARY = "Legendary"


class GamePhase(Enum):
    DRAW = "draw"
    MANA = "mana"
    PLACEMENT = "placement"
    REVEAL = "reveal"
    RESOLVE = "resolve"
    CLEANUP = "cleanup"
    MATCH_OVER = "match_over"


class Row(Enum):
    FRONT = "front"
    BACK = "back"


class Player(Enum):
    ONE = 1
    TWO = 2


# ---------------------------------------------------------------------------
# Type Advantage Table
# Outer key ATTACKS inner key. Value is damage multiplier.
# ---------------------------------------------------------------------------

TYPE_MATCHUP: dict[CardType, dict[CardType, float]] = {
    CardType.SPECTER: {
        CardType.SPECTER:  1.0,
        CardType.REVENANT: 0.75,   # weak to Revenant
        CardType.PHANTOM:  1.0,
        CardType.BEHEMOTH: 1.5,    # beats Behemoth
    },
    CardType.REVENANT: {
        CardType.SPECTER:  1.5,    # beats Specter
        CardType.REVENANT: 1.0,
        CardType.PHANTOM:  0.75,   # weak to Phantom
        CardType.BEHEMOTH: 1.0,
    },
    CardType.PHANTOM: {
        CardType.SPECTER:  1.0,
        CardType.REVENANT: 1.5,    # beats Revenant
        CardType.PHANTOM:  1.0,
        CardType.BEHEMOTH: 0.75,   # weak to Behemoth
    },
    CardType.BEHEMOTH: {
        CardType.SPECTER:  0.75,   # weak to Specter
        CardType.REVENANT: 1.0,
        CardType.PHANTOM:  1.5,    # beats Phantom
        CardType.BEHEMOTH: 1.0,
    },
}


# ---------------------------------------------------------------------------
# Ability (simple passive or triggered)
# ---------------------------------------------------------------------------

class AbilityTrigger(Enum):
    ON_ATTACK = "on_attack"
    ON_DEATH = "on_death"
    ON_SURVIVE_ROUND = "on_survive_round"
    PASSIVE = "passive"


class AbilityEffect(Enum):
    LIFESTEAL = "lifesteal"           # Heal self for % of damage dealt
    THORNS = "thorns"                 # Attacker takes % of damage back
    LAST_STAND = "last_stand"         # Gains +ATK when below 50% HP
    GHOST_STEP = "ghost_step"         # Ignores back-row protection once
    VEIL_ECHO = "veil_echo"           # On death: deal half attack to killer
    ARMOR = "armor"                   # Reduces incoming damage by flat amount


@dataclass
class Ability:
    trigger: AbilityTrigger
    effect: AbilityEffect
    value: float   # Multiplier or flat value depending on effect
    description: str


# ---------------------------------------------------------------------------
# Card Definition (the template, shared across all copies)
# ---------------------------------------------------------------------------

@dataclass
class CardDefinition:
    id: str
    name: str
    card_type: CardType
    rarity: Rarity
    base_attack: int
    base_defense: int
    speed: int          # 1–10, higher acts first
    mana_cost: int      # 1–7
    ability: Optional[Ability]
    lore: str
    art_url: str = ""

    def xp_threshold(self, level: int) -> int:
        return {1: 100, 2: 250, 3: 500, 4: 1000}.get(level, 9999)


# ---------------------------------------------------------------------------
# Card Instance (a player's owned copy, with level/XP/state)
# ---------------------------------------------------------------------------

@dataclass
class CardInstance:
    instance_id: str
    definition: CardDefinition
    owner: Player
    level: int = 1
    xp: int = 0
    consecutive_losses: int = 0   # 3 = Dormancy
    is_dormant: bool = False

    # Runtime stats (base + level bonuses)
    @property
    def attack(self) -> int:
        return self.definition.base_attack + (self.level - 1)

    @property
    def max_defense(self) -> int:
        return self.definition.base_defense + (self.level - 1) * 2

    def level_up(self) -> bool:
        """Returns True if leveled up."""
        threshold = self.definition.xp_threshold(self.level)
        if self.xp >= threshold and self.level < 5:
            self.level += 1
            self.xp -= threshold
            return True
        return False

    def add_xp(self, amount: int) -> bool:
        self.xp += amount
        return self.level_up()


# ---------------------------------------------------------------------------
# Board Cell
# ---------------------------------------------------------------------------

@dataclass
class BoardCell:
    col: int           # 0–3
    row: Row
    owner: Player
    card: Optional[BoardCard] = None


@dataclass
class BoardCard:
    """A card placed on the board during a round, with runtime HP."""
    instance: CardInstance
    current_hp: int
    col: int
    row: Row
    owner: Player
    face_down: bool = True      # Hidden until reveal phase
    has_attacked: bool = False
    position_bonus_attack: int = 0   # Applied during resolve

    @property
    def is_alive(self) -> bool:
        return self.current_hp > 0

    @property
    def effective_attack(self) -> int:
        return self.instance.attack + self.position_bonus_attack


# ---------------------------------------------------------------------------
# Board
# ---------------------------------------------------------------------------

@dataclass
class Board:
    """
    4x4 grid. Indexed by (col, row, player).
    Each player owns 2 rows: front and back.
    """
    cells: dict[tuple[int, Row, Player], BoardCard] = field(default_factory=dict)

    def place(self, card: BoardCard):
        key = (card.col, card.row, card.owner)
        if key in self.cells:
            raise ValueError(f"Cell {key} already occupied")
        self.cells[key] = card

    def get(self, col: int, row: Row, owner: Player) -> Optional[BoardCard]:
        return self.cells.get((col, row, owner))

    def remove(self, col: int, row: Row, owner: Player):
        self.cells.pop((col, row, owner), None)

    def cards_for(self, owner: Player) -> list[BoardCard]:
        return [c for c in self.cells.values() if c.owner == owner]

    def front_row_for(self, owner: Player) -> list[BoardCard]:
        return [c for c in self.cells.values()
                if c.owner == owner and c.row == Row.FRONT]

    def back_row_for(self, owner: Player) -> list[BoardCard]:
        return [c for c in self.cells.values()
                if c.owner == owner and c.row == Row.BACK]

    def all_cards(self) -> list[BoardCard]:
        return list(self.cells.values())


# ---------------------------------------------------------------------------
# Player State
# ---------------------------------------------------------------------------

@dataclass
class PlayerState:
    player: Player
    hand: list[CardInstance] = field(default_factory=list)
    deck: list[CardInstance] = field(default_factory=list)
    mana: int = 3
    veil_surge_used: bool = False
    score: int = 0          # Points won (match level)
    hp: int = 20            # Veilweaver health (future mechanic hook)


# ---------------------------------------------------------------------------
# Battle Events (what the DM agent reads)
# ---------------------------------------------------------------------------

@dataclass
class CombatEvent:
    order: int
    attacker_name: str
    attacker_type: str
    attacker_level: int
    attacker_owner: Player
    defender_name: str
    defender_type: str
    defender_level: int
    defender_owner: Player
    type_multiplier: float
    raw_attack: int
    damage_dealt: int
    position_bonus: int
    defender_destroyed: bool
    ability_triggered: Optional[str] = None
    ability_effect_description: Optional[str] = None


@dataclass
class RoundResult:
    round_number: int
    events: list[CombatEvent]
    veil_collapse: bool
    p1_surviving_defense: int
    p2_surviving_defense: int
    round_winner: Optional[Player]    # None = tie
    round_points_awarded: int         # 1 normal, 2 full wipe
    match_score: dict[str, int]
    match_winner: Optional[Player]
    flanking_applied: Optional[Player]   # Which player got flanking bonus


# ---------------------------------------------------------------------------
# Full Game State
# ---------------------------------------------------------------------------

@dataclass
class GameState:
    game_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    player1: PlayerState = field(default_factory=lambda: PlayerState(Player.ONE))
    player2: PlayerState = field(default_factory=lambda: PlayerState(Player.TWO))
    board: Board = field(default_factory=Board)
    current_round: int = 1
    phase: GamePhase = GamePhase.DRAW
    round_history: list[RoundResult] = field(default_factory=list)
    match_winner: Optional[Player] = None

    def get_player_state(self, player: Player) -> PlayerState:
        return self.player1 if player == Player.ONE else self.player2

    def opponent(self, player: Player) -> Player:
        return Player.TWO if player == Player.ONE else Player.ONE
