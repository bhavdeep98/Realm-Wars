"""
Veilborn — Supabase Repository Layer
All database operations in one place. No SQL outside this file.

Usage:
    from db.repository import VeilbornRepository
    repo = VeilbornRepository(supabase_url, supabase_key)

    # Get a player's cards
    cards = await repo.get_player_cards(player_id)

    # Save round result
    await repo.save_round(match_id, round_number, battle_log, narration, image_url)
"""

from __future__ import annotations
import json
import uuid
import random
from datetime import datetime, timedelta
from typing import Optional
from dataclasses import dataclass

# pip install supabase
from supabase import create_client, Client


# ---------------------------------------------------------------------------
# Data Transfer Objects (what the repository returns to callers)
# ---------------------------------------------------------------------------

@dataclass
class PlayerProfile:
    id: str
    username: str
    display_name: str
    veilweaver_level: int
    total_xp: int
    shards: int
    crystals: int
    matches_played: int
    matches_won: int
    elo_rating: int
    win_streak: int


@dataclass
class OwnedCard:
    id: str                     # player_cards.id (instance)
    definition_id: str          # card_definitions.id
    name: str
    card_type: str
    rarity: str
    base_attack: int
    base_defense: int
    speed: int
    mana_cost: int
    ability_trigger: Optional[str]
    ability_effect: Optional[str]
    ability_value: Optional[float]
    ability_desc: Optional[str]
    art_url: str
    lore: str
    level: int
    xp: int
    consecutive_losses: int
    is_dormant: bool
    dormant_until: Optional[str]


@dataclass
class MatchSummary:
    id: str
    player1_id: str
    player2_id: Optional[str]
    winner_id: Optional[str]
    status: str
    player1_score: int
    player2_score: int
    current_round: int
    created_at: str
    completed_at: Optional[str]


# ---------------------------------------------------------------------------
# Repository
# ---------------------------------------------------------------------------

class VeilbornRepository:

    def __init__(self, supabase_url: str, supabase_key: str):
        self.client: Client = create_client(supabase_url, supabase_key)

    # -----------------------------------------------------------------------
    # PROFILES
    # -----------------------------------------------------------------------

    async def get_profile(self, player_id: str) -> Optional[PlayerProfile]:
        """Fetch a player's profile."""
        result = (
            self.client.table("profiles")
            .select("*")
            .eq("id", player_id)
            .single()
            .execute()
        )
        if not result.data:
            return None
        return self._row_to_profile(result.data)

    async def update_profile_stats(
        self,
        player_id: str,
        won: bool,
        elo_delta: int,
        xp_earned: int,
    ) -> None:
        """
        Update profile after a match completes.
        Increments matches_played, conditionally increments won,
        updates ELO and XP, manages win streak.
        """
        profile = await self.get_profile(player_id)
        if not profile:
            return

        new_streak = (profile.win_streak + 1) if won else 0
        new_xp = profile.total_xp + xp_earned
        new_level = self._xp_to_veilweaver_level(new_xp)

        self.client.table("profiles").update({
            "matches_played": profile.matches_played + 1,
            "matches_won": profile.matches_won + (1 if won else 0),
            "elo_rating": max(100, profile.elo_rating + elo_delta),
            "win_streak": new_streak,
            "best_win_streak": max(profile.win_streak, new_streak),
            "total_xp": new_xp,
            "veilweaver_level": new_level,
        }).eq("id", player_id).execute()

    async def adjust_currency(
        self,
        player_id: str,
        shard_delta: int = 0,
        crystal_delta: int = 0,
    ) -> None:
        """Add or subtract currency. Raises if result would go negative."""
        profile = await self.get_profile(player_id)
        if not profile:
            raise ValueError(f"Player {player_id} not found")

        new_shards = profile.shards + shard_delta
        new_crystals = profile.crystals + crystal_delta

        if new_shards < 0:
            raise ValueError(f"Insufficient shards: have {profile.shards}, need {abs(shard_delta)}")
        if new_crystals < 0:
            raise ValueError(f"Insufficient crystals: have {profile.crystals}, need {abs(crystal_delta)}")

        self.client.table("profiles").update({
            "shards": new_shards,
            "crystals": new_crystals,
        }).eq("id", player_id).execute()

    # -----------------------------------------------------------------------
    # CARDS
    # -----------------------------------------------------------------------

    async def get_player_cards(self, player_id: str) -> list[OwnedCard]:
        """Get all cards owned by a player, joined with definitions."""
        result = (
            self.client.table("player_cards")
            .select("*, card_definitions(*)")
            .eq("player_id", player_id)
            .execute()
        )
        return [self._row_to_owned_card(row) for row in (result.data or [])]

    async def get_active_deck_cards(self, player_id: str) -> list[OwnedCard]:
        """Get cards in the player's active deck."""
        result = (
            self.client.table("deck_cards")
            .select("player_cards(*, card_definitions(*))")
            .eq("decks.player_id", player_id)
            .eq("decks.is_active", True)
            .execute()
        )
        return [self._row_to_owned_card(row["player_cards"]) for row in (result.data or [])]

    async def grant_card(
        self,
        player_id: str,
        card_definition_id: str,
        acquired_via: str = "pack",
    ) -> str:
        """Grant a card to a player. Returns the new player_card id."""
        result = (
            self.client.table("player_cards")
            .insert({
                "player_id": player_id,
                "card_definition_id": card_definition_id,
                "acquired_via": acquired_via,
            })
            .execute()
        )
        return result.data[0]["id"]

    async def update_card_after_match(
        self,
        player_card_id: str,
        xp_gained: int,
        lost_round: bool,
    ) -> dict:
        """
        Update a card's XP and loss streak after a match.
        Returns the updated card state including new level if leveled up.
        """
        # Fetch current state
        result = (
            self.client.table("player_cards")
            .select("level, xp, consecutive_losses, is_dormant")
            .eq("id", player_card_id)
            .single()
            .execute()
        )
        card = result.data

        new_xp = card["xp"] + xp_gained
        new_level = card["level"]
        new_losses = (card["consecutive_losses"] + 1) if lost_round else 0

        # Level up logic (matches engine)
        xp_thresholds = {1: 100, 2: 250, 3: 500, 4: 1000}
        while new_level < 5 and new_xp >= xp_thresholds.get(new_level, 9999):
            new_xp -= xp_thresholds[new_level]
            new_level += 1

        # Dormancy
        is_dormant = new_losses >= 3
        dormant_until = (
            (datetime.utcnow() + timedelta(hours=24)).isoformat()
            if is_dormant else None
        )

        self.client.table("player_cards").update({
            "xp": new_xp,
            "level": new_level,
            "consecutive_losses": new_losses,
            "is_dormant": is_dormant,
            "dormant_until": dormant_until,
        }).eq("id", player_card_id).execute()

        return {
            "level": new_level,
            "xp": new_xp,
            "leveled_up": new_level > card["level"],
            "is_dormant": is_dormant,
        }

    # -----------------------------------------------------------------------
    # DECKS
    # -----------------------------------------------------------------------

    async def create_deck(self, player_id: str, name: str, set_active: bool = False) -> str:
        """Create a new empty deck. Returns deck id."""
        result = (
            self.client.table("decks")
            .insert({"player_id": player_id, "name": name, "is_active": set_active})
            .execute()
        )
        return result.data[0]["id"]

    async def add_card_to_deck(self, deck_id: str, player_card_id: str, slot_order: int = 0):
        """Add a card to a deck. Raises if deck is full (10 cards)."""
        self.client.table("deck_cards").insert({
            "deck_id": deck_id,
            "player_card_id": player_card_id,
            "slot_order": slot_order,
        }).execute()

    async def get_player_decks(self, player_id: str) -> list[dict]:
        """Get all decks for a player with card counts."""
        result = (
            self.client.table("decks")
            .select("*, deck_cards(count)")
            .eq("player_id", player_id)
            .execute()
        )
        return result.data or []

    # -----------------------------------------------------------------------
    # MATCHES
    # -----------------------------------------------------------------------

    async def create_match(
        self,
        player1_id: str,
        player1_deck_id: str,
        elo_rating: int,
        is_ranked: bool = True,
    ) -> str:
        """Create a new match and return its id."""
        match_id = str(uuid.uuid4())
        self.client.table("matches").insert({
            "id": match_id,
            "player1_id": player1_id,
            "player1_deck_id": player1_deck_id,
            "elo_bracket": elo_rating,
            "is_ranked": is_ranked,
            "realtime_channel": f"match:{match_id}",
            "status": "waiting",
        }).execute()
        return match_id

    async def join_match(
        self,
        match_id: str,
        player2_id: str,
        player2_deck_id: str,
    ) -> None:
        """Second player joins a waiting match."""
        self.client.table("matches").update({
            "player2_id": player2_id,
            "player2_deck_id": player2_deck_id,
            "status": "active",
            "started_at": datetime.utcnow().isoformat(),
        }).eq("id", match_id).execute()

    async def find_match_in_queue(self, elo_rating: int, bracket_width: int = 100) -> Optional[str]:
        """
        Find a waiting match within ELO bracket.
        Returns match_id if found, None if no match available.
        """
        result = (
            self.client.table("matches")
            .select("id, elo_bracket")
            .eq("status", "waiting")
            .gte("elo_bracket", elo_rating - bracket_width)
            .lte("elo_bracket", elo_rating + bracket_width)
            .order("created_at")
            .limit(1)
            .execute()
        )
        if result.data:
            return result.data[0]["id"]
        return None

    async def get_match(self, match_id: str) -> Optional[MatchSummary]:
        """Fetch a match by id."""
        result = (
            self.client.table("matches")
            .select("*")
            .eq("id", match_id)
            .single()
            .execute()
        )
        if not result.data:
            return None
        return self._row_to_match_summary(result.data)

    async def update_match_phase(
        self,
        match_id: str,
        current_round: int,
        current_phase: str,
        player1_score: int,
        player2_score: int,
    ) -> None:
        """Update match state after each phase transition."""
        self.client.table("matches").update({
            "current_round": current_round,
            "current_phase": current_phase,
            "player1_score": player1_score,
            "player2_score": player2_score,
        }).eq("id", match_id).execute()

    async def complete_match(
        self,
        match_id: str,
        winner_id: Optional[str],
        player1_score: int,
        player2_score: int,
        player1_elo_delta: int,
        player2_elo_delta: int,
    ) -> None:
        """Mark a match as completed and write ELO deltas."""
        self.client.table("matches").update({
            "status": "completed" if winner_id else "draw",
            "winner_id": winner_id,
            "player1_score": player1_score,
            "player2_score": player2_score,
            "player1_elo_delta": player1_elo_delta,
            "player2_elo_delta": player2_elo_delta,
            "completed_at": datetime.utcnow().isoformat(),
        }).eq("id", match_id).execute()

    async def get_recent_matches(self, player_id: str, limit: int = 10) -> list[MatchSummary]:
        """Get a player's recent match history."""
        result = (
            self.client.table("matches")
            .select("*")
            .or_(f"player1_id.eq.{player_id},player2_id.eq.{player_id}")
            .in_("status", ["completed", "draw"])
            .order("completed_at", desc=True)
            .limit(limit)
            .execute()
        )
        return [self._row_to_match_summary(row) for row in (result.data or [])]

    # -----------------------------------------------------------------------
    # MATCH ROUNDS
    # -----------------------------------------------------------------------

    async def save_round(
        self,
        match_id: str,
        round_number: int,
        battle_log: dict,
        narration_title: Optional[str] = None,
        narration_text: Optional[str] = None,
        narration_tone: Optional[str] = None,
        narration_key_moment: Optional[str] = None,
        image_url: Optional[str] = None,
        image_prompt: Optional[str] = None,
        round_winner_id: Optional[str] = None,
        points_awarded: int = 0,
        veil_collapse: bool = False,
        p1_surviving_defense: int = 0,
        p2_surviving_defense: int = 0,
    ) -> str:
        """Save a completed round's full record. Returns round record id."""
        result = (
            self.client.table("match_rounds")
            .insert({
                "match_id": match_id,
                "round_number": round_number,
                "battle_log": battle_log,
                "narration_title": narration_title,
                "narration_text": narration_text,
                "narration_tone": narration_tone,
                "narration_key_moment": narration_key_moment,
                "image_url": image_url,
                "image_prompt": image_prompt,
                "round_winner_id": round_winner_id,
                "points_awarded": points_awarded,
                "veil_collapse": veil_collapse,
                "p1_surviving_defense": p1_surviving_defense,
                "p2_surviving_defense": p2_surviving_defense,
            })
            .execute()
        )
        return result.data[0]["id"]

    async def get_match_rounds(self, match_id: str) -> list[dict]:
        """Get all rounds for a match, ordered by round number."""
        result = (
            self.client.table("match_rounds")
            .select("*")
            .eq("match_id", match_id)
            .order("round_number")
            .execute()
        )
        return result.data or []

    async def update_round_image(self, match_id: str, round_number: int, image_url: str) -> None:
        """Update a round's image URL after async generation completes."""
        self.client.table("match_rounds").update({
            "image_url": image_url,
        }).eq("match_id", match_id).eq("round_number", round_number).execute()

    # -----------------------------------------------------------------------
    # MATCH PLACEMENTS
    # -----------------------------------------------------------------------

    async def save_placement(
        self,
        match_id: str,
        round_number: int,
        player_id: str,
        player_card_id: str,
        col: int,
        row: str,
        mana_spent: int,
    ) -> None:
        """Record a card placement action."""
        self.client.table("match_placements").insert({
            "match_id": match_id,
            "round_number": round_number,
            "player_id": player_id,
            "player_card_id": player_card_id,
            "col": col,
            "row": row,
            "mana_spent": mana_spent,
            "face_down": True,
        }).execute()

    async def reveal_placements(self, match_id: str, round_number: int) -> None:
        """Flip all placements in a round to face_down=False."""
        self.client.table("match_placements").update({
            "face_down": False,
        }).eq("match_id", match_id).eq("round_number", round_number).execute()

    # -----------------------------------------------------------------------
    # PACK SYSTEM
    # -----------------------------------------------------------------------

    async def open_pack(
        self,
        player_id: str,
        pack_id: str,
        currency_type: str,
        revenuecat_tx: Optional[str] = None,
    ) -> list[str]:
        """
        Open a card pack. Returns list of card_definition_ids awarded.
        Handles currency deduction, weighted card draw, and card granting.
        """
        # Fetch pack definition
        pack_result = (
            self.client.table("card_packs")
            .select("*")
            .eq("id", pack_id)
            .eq("is_active", True)
            .single()
            .execute()
        )
        pack = pack_result.data
        if not pack:
            raise ValueError(f"Pack {pack_id} not found or inactive")

        # Deduct currency (skip for IAP — RevenueCat handles it)
        if currency_type == "shards" and pack["shard_cost"]:
            await self.adjust_currency(player_id, shard_delta=-pack["shard_cost"])
        elif currency_type == "crystals" and pack["crystal_cost"]:
            await self.adjust_currency(player_id, crystal_delta=-pack["crystal_cost"])

        # Draw cards
        drawn_card_ids = await self._draw_cards(
            count=pack["cards_per_pack"],
            guaranteed_rarity=pack.get("guaranteed_rarity"),
        )

        # Grant cards to player and record purchase
        awarded_instance_ids = []
        for card_def_id in drawn_card_ids:
            instance_id = await self.grant_card(player_id, card_def_id, acquired_via="pack")
            awarded_instance_ids.append(instance_id)

        # Record purchase
        amount_paid = pack["shard_cost"] or pack["crystal_cost"]
        self.client.table("pack_purchases").insert({
            "player_id": player_id,
            "pack_id": pack_id,
            "cards_awarded": awarded_instance_ids,
            "currency_type": currency_type,
            "amount_paid": amount_paid if currency_type != "iap" else None,
            "revenuecat_tx": revenuecat_tx,
        }).execute()

        return drawn_card_ids

    async def _draw_cards(
        self,
        count: int,
        guaranteed_rarity: Optional[str] = None,
    ) -> list[str]:
        """
        Weighted random card draw from card_definitions.
        Ensures at least one card of guaranteed_rarity if specified.
        """
        # Fetch all active card definitions
        result = (
            self.client.table("card_definitions")
            .select("id, rarity, pack_weight")
            .eq("is_active", True)
            .execute()
        )
        all_cards = result.data or []

        rarity_order = {"Common": 0, "Rare": 1, "Epic": 2, "Legendary": 3}
        drawn = []

        # Guarantee at least one card of required rarity
        if guaranteed_rarity:
            eligible = [
                c for c in all_cards
                if rarity_order.get(c["rarity"], 0) >= rarity_order.get(guaranteed_rarity, 0)
            ]
            if eligible:
                weights = [c["pack_weight"] for c in eligible]
                chosen = random.choices(eligible, weights=weights, k=1)[0]
                drawn.append(chosen["id"])
                count -= 1

        # Draw remaining cards (weighted by pack_weight)
        weights = [c["pack_weight"] for c in all_cards]
        remaining = random.choices(all_cards, weights=weights, k=count)
        drawn.extend([c["id"] for c in remaining])

        return drawn

    # -----------------------------------------------------------------------
    # BATTLE PASS
    # -----------------------------------------------------------------------

    async def get_battle_pass_progress(
        self,
        player_id: str,
        battle_pass_id: str,
    ) -> Optional[dict]:
        """Get a player's progress in a specific battle pass."""
        result = (
            self.client.table("battle_pass_progress")
            .select("*")
            .eq("player_id", player_id)
            .eq("battle_pass_id", battle_pass_id)
            .single()
            .execute()
        )
        return result.data

    async def add_battle_pass_xp(
        self,
        player_id: str,
        battle_pass_id: str,
        xp_amount: int,
    ) -> dict:
        """
        Add XP to a player's battle pass progress.
        Returns new state including any tiers unlocked.
        """
        progress = await self.get_battle_pass_progress(player_id, battle_pass_id)
        if not progress:
            # Auto-enroll with free track
            self.client.table("battle_pass_progress").insert({
                "player_id": player_id,
                "battle_pass_id": battle_pass_id,
                "is_premium": False,
                "current_xp": xp_amount,
            }).execute()
            return {"current_xp": xp_amount, "tiers_unlocked": []}

        new_xp = progress["current_xp"] + xp_amount
        self.client.table("battle_pass_progress").update({
            "current_xp": new_xp,
        }).eq("player_id", player_id).eq("battle_pass_id", battle_pass_id).execute()

        return {"current_xp": new_xp}

    async def purchase_battle_pass_premium(
        self,
        player_id: str,
        battle_pass_id: str,
        revenuecat_tx: str,
    ) -> None:
        """Unlock premium battle pass track for a player."""
        self.client.table("battle_pass_progress").upsert({
            "player_id": player_id,
            "battle_pass_id": battle_pass_id,
            "is_premium": True,
            "purchased_at": datetime.utcnow().isoformat(),
        }).execute()

    # -----------------------------------------------------------------------
    # LEADERBOARD
    # -----------------------------------------------------------------------

    async def get_leaderboard(self, limit: int = 50) -> list[dict]:
        """Top players by ELO rating."""
        result = (
            self.client.table("profiles")
            .select("username, display_name, elo_rating, matches_won, matches_played, veilweaver_level")
            .order("elo_rating", desc=True)
            .limit(limit)
            .execute()
        )
        return result.data or []

    # -----------------------------------------------------------------------
    # STARTER PACK (new player onboarding)
    # -----------------------------------------------------------------------

    async def grant_starter_collection(self, player_id: str) -> list[str]:
        """
        Grant a new player their starter cards and create their first deck.
        Called once after profile creation.
        Gives one of each Common card + one Rare.
        """
        starter_card_ids = [
            "spec_003",   # Ashling (Common Specter)
            "rev_003",    # Duskwarden (Common Revenant)
            "phan_002",   # The Lurking Shade (Common Phantom)
            "beh_002",    # Bonecrag (Common Behemoth)
            "spec_001",   # Morthex the Hollow (Common Specter w/ ability)
            "rev_002",    # Serath the Unburied (Common Revenant w/ ability)
        ]

        instance_ids = []
        for card_id in starter_card_ids:
            iid = await self.grant_card(player_id, card_id, acquired_via="starter")
            instance_ids.append(iid)

        # Create and populate starter deck
        deck_id = await self.create_deck(player_id, "Starter Deck", set_active=True)
        for i, iid in enumerate(instance_ids):
            await self.add_card_to_deck(deck_id, iid, slot_order=i)

        return instance_ids

    # -----------------------------------------------------------------------
    # ELO CALCULATION
    # -----------------------------------------------------------------------

    def calculate_elo_delta(
        self,
        winner_elo: int,
        loser_elo: int,
        k_factor: int = 32,
    ) -> tuple[int, int]:
        """
        Standard ELO calculation.
        Returns (winner_delta, loser_delta).
        """
        expected_winner = 1 / (1 + 10 ** ((loser_elo - winner_elo) / 400))
        expected_loser = 1 - expected_winner

        winner_delta = round(k_factor * (1 - expected_winner))
        loser_delta = round(k_factor * (0 - expected_loser))

        return winner_delta, loser_delta

    # -----------------------------------------------------------------------
    # Private helpers
    # -----------------------------------------------------------------------

    def _row_to_profile(self, row: dict) -> PlayerProfile:
        return PlayerProfile(
            id=row["id"],
            username=row["username"],
            display_name=row["display_name"],
            veilweaver_level=row["veilweaver_level"],
            total_xp=row["total_xp"],
            shards=row["shards"],
            crystals=row["crystals"],
            matches_played=row["matches_played"],
            matches_won=row["matches_won"],
            elo_rating=row["elo_rating"],
            win_streak=row["win_streak"],
        )

    def _row_to_owned_card(self, row: dict) -> OwnedCard:
        defn = row.get("card_definitions", {}) or row
        return OwnedCard(
            id=row["id"],
            definition_id=row["card_definition_id"],
            name=defn["name"],
            card_type=defn["card_type"],
            rarity=defn["rarity"],
            base_attack=defn["base_attack"],
            base_defense=defn["base_defense"],
            speed=defn["speed"],
            mana_cost=defn["mana_cost"],
            ability_trigger=defn.get("ability_trigger"),
            ability_effect=defn.get("ability_effect"),
            ability_value=defn.get("ability_value"),
            ability_desc=defn.get("ability_desc"),
            art_url=defn.get("art_url", ""),
            lore=defn.get("lore", ""),
            level=row["level"],
            xp=row["xp"],
            consecutive_losses=row["consecutive_losses"],
            is_dormant=row["is_dormant"],
            dormant_until=row.get("dormant_until"),
        )

    def _row_to_match_summary(self, row: dict) -> MatchSummary:
        return MatchSummary(
            id=row["id"],
            player1_id=row["player1_id"],
            player2_id=row.get("player2_id"),
            winner_id=row.get("winner_id"),
            status=row["status"],
            player1_score=row["player1_score"],
            player2_score=row["player2_score"],
            current_round=row["current_round"],
            created_at=row["created_at"],
            completed_at=row.get("completed_at"),
        )

    def _xp_to_veilweaver_level(self, total_xp: int) -> int:
        """Convert total XP to Veilweaver level (account level, not card level)."""
        thresholds = [0, 500, 1500, 3000, 5000, 8000, 12000, 17000, 23000, 30000]
        for level, threshold in enumerate(thresholds, start=1):
            if total_xp < threshold:
                return level - 1
        return len(thresholds)
