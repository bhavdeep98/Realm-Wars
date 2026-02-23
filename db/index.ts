// =============================================================================
// Veilborn — Supabase Edge Function: resolve-round
// Deployed to: supabase/functions/resolve-round/index.ts
//
// Called by the Flutter app after both players submit placements.
// Runs the rules engine (via Python subprocess OR via ported TS logic),
// calls the DM agent, saves results, broadcasts via Realtime.
//
// POST /functions/v1/resolve-round
// Body: { match_id: string, round_number: number }
// Auth: Bearer token (player JWT)
// =============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// ---------------------------------------------------------------------------
// Types (mirror of Python models)
// ---------------------------------------------------------------------------

type CardType = "Specter" | "Revenant" | "Phantom" | "Behemoth";

const TYPE_MATCHUP: Record<CardType, Record<CardType, number>> = {
  Specter:  { Specter: 1.0, Revenant: 0.75, Phantom: 1.0, Behemoth: 1.5 },
  Revenant: { Specter: 1.5, Revenant: 1.0,  Phantom: 0.75, Behemoth: 1.0 },
  Phantom:  { Specter: 1.0, Revenant: 1.5,  Phantom: 1.0, Behemoth: 0.75 },
  Behemoth: { Specter: 0.75, Revenant: 1.0, Phantom: 1.5, Behemoth: 1.0 },
};

interface PlacedCard {
  player_card_id: string;
  player_id: string;
  card_definition_id: string;
  name: string;
  card_type: CardType;
  level: number;
  base_attack: number;
  base_defense: number;
  speed: number;
  mana_cost: number;
  ability_effect: string | null;
  ability_trigger: string | null;
  ability_value: number | null;
  col: number;
  row: "front" | "back";
  current_hp: number;
  position_bonus: number;
}

interface CombatEvent {
  order: number;
  attacker: { name: string; type: string; level: number; owner: string };
  defender: { name: string; type: string; level: number; owner: string };
  type_advantage: string;
  damage_dealt: number;
  position_bonus: number;
  defender_destroyed: boolean;
  ability?: { name: string; description: string };
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response("Unauthorized", { status: 401 });
  }

  const { match_id, round_number } = await req.json();
  if (!match_id || !round_number) {
    return new Response("Missing match_id or round_number", { status: 400 });
  }

  // Use service role for server-side operations
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  try {
    // 1. Fetch match and verify it's active
    const { data: match, error: matchError } = await supabase
      .from("matches")
      .select("*, profiles!player1_id(username), profiles!player2_id(username)")
      .eq("id", match_id)
      .eq("status", "active")
      .single();

    if (matchError || !match) {
      return new Response(JSON.stringify({ error: "Match not found or not active" }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }

    // 2. Fetch all placements for this round
    const { data: placements } = await supabase
      .from("match_placements")
      .select(`
        *,
        player_cards(
          id, level, xp,
          card_definitions(id, name, card_type, base_attack, base_defense, speed, mana_cost, ability_effect, ability_trigger, ability_value)
        )
      `)
      .eq("match_id", match_id)
      .eq("round_number", round_number);

    if (!placements || placements.length === 0) {
      return new Response(JSON.stringify({ error: "No placements found for this round" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // 3. Build placed card objects
    const placedCards: PlacedCard[] = placements.map((p: any) => {
      const pc = p.player_cards;
      const def = pc.card_definitions;
      return {
        player_card_id: pc.id,
        player_id: p.player_id,
        card_definition_id: def.id,
        name: def.name,
        card_type: def.card_type as CardType,
        level: pc.level,
        base_attack: def.base_attack,
        base_defense: def.base_defense,
        speed: def.speed,
        mana_cost: def.mana_cost,
        ability_effect: def.ability_effect,
        ability_trigger: def.ability_trigger,
        ability_value: def.ability_value,
        col: p.col,
        row: p.row,
        current_hp: def.base_defense + (pc.level - 1) * 2,
        position_bonus: 0,
      };
    });

    // 4. Flip placements to revealed
    await supabase
      .from("match_placements")
      .update({ face_down: false })
      .eq("match_id", match_id)
      .eq("round_number", round_number);

    // 5. Run deterministic combat resolution
    const { events, p1Defense, p2Defense } = resolveCombat(
      placedCards,
      match.player1_id,
      match.player2_id,
      round_number === 5
    );

    // 6. Determine round winner and points
    const isVeilCollapse = round_number === 5;
    const p2Wiped = p2Defense === 0 && events.some(e => e.defender.owner === match.profiles__player2_id?.username && e.defender_destroyed);
    const p1Wiped = p1Defense === 0 && events.some(e => e.defender.owner === match.profiles__player1_id?.username && e.defender_destroyed);

    let roundWinnerId: string | null = null;
    let pointsAwarded = 0;

    if (p1Wiped && !p2Wiped) {
      roundWinnerId = match.player2_id;
      pointsAwarded = 2;
    } else if (p2Wiped && !p1Wiped) {
      roundWinnerId = match.player1_id;
      pointsAwarded = 2;
    } else if (p1Defense > p2Defense) {
      roundWinnerId = match.player1_id;
      pointsAwarded = 1;
    } else if (p2Defense > p1Defense) {
      roundWinnerId = match.player2_id;
      pointsAwarded = 1;
    }

    // Update scores
    const newP1Score = match.player1_score + (roundWinnerId === match.player1_id ? pointsAwarded : 0);
    const newP2Score = match.player2_score + (roundWinnerId === match.player2_id ? pointsAwarded : 0);

    // Check match winner
    let matchWinnerId: string | null = null;
    if (newP1Score >= 3) matchWinnerId = match.player1_id;
    else if (newP2Score >= 3) matchWinnerId = match.player2_id;
    else if (round_number >= 5) {
      if (newP1Score > newP2Score) matchWinnerId = match.player1_id;
      else if (newP2Score > newP1Score) matchWinnerId = match.player2_id;
    }

    // 7. Build BattleLog payload for DM agent
    const p1Name = match["profiles!player1_id"]?.username || "Player 1";
    const p2Name = match["profiles!player2_id"]?.username || "Player 2";

    const battleLog = {
      round: round_number,
      veil_collapse: isVeilCollapse,
      flanking_bonus_awarded_to: null, // simplified for edge function
      combat_events: events,
      round_outcome: {
        p1_surviving_defense: p1Defense,
        p2_surviving_defense: p2Defense,
        winner: roundWinnerId === match.player1_id ? p1Name : roundWinnerId === match.player2_id ? p2Name : "Tie",
        points_awarded: pointsAwarded,
        reason: pointsAwarded === 2 ? "Full wipe (+2 points)" : "Higher surviving defense (+1 point)",
      },
      match_score: { [p1Name]: newP1Score, [p2Name]: newP2Score },
      match_winner: matchWinnerId === match.player1_id ? p1Name : matchWinnerId === match.player2_id ? p2Name : null,
    };

    // 8. Call DM Agent (Claude API)
    const narration = await callDMAgent(battleLog, p1Name, p2Name);

    // 9. Save round to DB
    await supabase.from("match_rounds").insert({
      match_id,
      round_number,
      battle_log: battleLog,
      narration_title: narration.round_title,
      narration_text: narration.narration,
      narration_tone: narration.tone,
      narration_key_moment: narration.key_moment,
      round_winner_id: roundWinnerId,
      points_awarded: pointsAwarded,
      veil_collapse: isVeilCollapse,
      p1_surviving_defense: p1Defense,
      p2_surviving_defense: p2Defense,
    });

    // 10. Update match state
    const updatePayload: any = {
      current_round: matchWinnerId ? round_number : round_number + 1,
      current_phase: matchWinnerId ? "match_over" : "draw",
      player1_score: newP1Score,
      player2_score: newP2Score,
    };

    if (matchWinnerId) {
      updatePayload.status = "completed";
      updatePayload.winner_id = matchWinnerId;
      updatePayload.completed_at = new Date().toISOString();
    }

    await supabase.from("matches").update(updatePayload).eq("id", match_id);

    // 11. Broadcast via Supabase Realtime
    await supabase.channel(`match:${match_id}`).send({
      type: "broadcast",
      event: "round_resolved",
      payload: {
        round_number,
        battle_log: battleLog,
        narration,
        match_winner_id: matchWinnerId,
        new_p1_score: newP1Score,
        new_p2_score: newP2Score,
      },
    });

    return new Response(JSON.stringify({
      success: true,
      round_number,
      narration,
      battle_log: battleLog,
      match_winner_id: matchWinnerId,
    }), {
      headers: { "Content-Type": "application/json" },
    });

  } catch (err) {
    console.error("resolve-round error:", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

// ---------------------------------------------------------------------------
// Deterministic combat resolver (TypeScript port of rules.py)
// ---------------------------------------------------------------------------

function resolveCombat(
  cards: PlacedCard[],
  p1Id: string,
  p2Id: string,
  veilCollapse: boolean
): { events: CombatEvent[]; p1Defense: number; p2Defense: number } {
  // Apply flanking bonus
  const p1Front = cards.filter(c => c.player_id === p1Id && c.row === "front");
  const p2Front = cards.filter(c => c.player_id === p2Id && c.row === "front");
  const p1Cols = new Set(p1Front.map(c => c.col));
  const p2Cols = new Set(p2Front.map(c => c.col));

  if (p1Cols.size >= 3 && p2Cols.size <= 2) {
    p1Front.forEach(c => c.position_bonus += 2);
  } else if (p2Cols.size >= 3 && p1Cols.size <= 2) {
    p2Front.forEach(c => c.position_bonus += 2);
  }

  // Apply column pressure
  for (const card of cards) {
    const opp = cards.find(c =>
      c.player_id !== card.player_id &&
      c.col === card.col &&
      c.row === "front" &&
      card.row === "front"
    );
    if (opp) {
      const mult = TYPE_MATCHUP[card.card_type][opp.card_type];
      if (mult === 1.5) card.position_bonus += 1;
    }
  }

  // Veil Collapse — all cards get +50% attack
  if (veilCollapse) {
    cards.forEach(c => c.position_bonus += Math.floor(c.base_attack * 0.5));
  }

  // Sort by speed (desc), then attack (desc)
  const sorted = [...cards].sort((a, b) => {
    const aAtk = a.base_attack + (a.level - 1) + a.position_bonus;
    const bAtk = b.base_attack + (b.level - 1) + b.position_bonus;
    return b.speed !== a.speed ? b.speed - a.speed : bAtk - aAtk;
  });

  const events: CombatEvent[] = [];
  let eventOrder = 0;

  for (const attacker of sorted) {
    if (attacker.current_hp <= 0) continue;

    const target = findTarget(attacker, cards);
    if (!target) continue;

    const atkValue = attacker.base_attack + (attacker.level - 1) + attacker.position_bonus;
    const mult = TYPE_MATCHUP[attacker.card_type][target.card_type];
    let damage = Math.floor(atkValue * mult);

    // Armor ability on defender
    if (target.ability_effect === "armor" && target.ability_value) {
      damage = Math.max(0, damage - target.ability_value);
    }

    target.current_hp -= damage;
    eventOrder++;

    const destroyed = target.current_hp <= 0;
    const ev: CombatEvent = {
      order: eventOrder,
      attacker: { name: attacker.name, type: attacker.card_type, level: attacker.level, owner: attacker.player_id },
      defender: { name: target.name, type: target.card_type, level: target.level, owner: target.player_id },
      type_advantage: mult === 1.5 ? "advantage (1.5x)" : mult === 0.75 ? "disadvantage (0.75x)" : "neutral (1.0x)",
      damage_dealt: damage,
      position_bonus: attacker.position_bonus,
      defender_destroyed: destroyed,
    };

    // Veil Echo on death
    if (destroyed && target.ability_effect === "veil_echo" && target.ability_value) {
      const echoDmg = Math.floor(target.base_attack * target.ability_value);
      attacker.current_hp -= echoDmg;
      ev.ability = { name: "Veil Echo", description: `Death echo dealt ${echoDmg} to killer` };
    }

    events.push(ev);
  }

  const p1Defense = cards
    .filter(c => c.player_id === p1Id && c.current_hp > 0)
    .reduce((sum, c) => sum + c.current_hp, 0);

  const p2Defense = cards
    .filter(c => c.player_id === p2Id && c.current_hp > 0)
    .reduce((sum, c) => sum + c.current_hp, 0);

  return { events, p1Defense, p2Defense };
}

function findTarget(attacker: PlacedCard, allCards: PlacedCard[]): PlacedCard | null {
  const enemies = allCards.filter(c => c.player_id !== attacker.player_id && c.current_hp > 0);

  function isTargetable(card: PlacedCard): boolean {
    if (card.row === "back") {
      const blocker = allCards.find(c =>
        c.player_id === card.player_id && c.col === card.col && c.row === "front" && c.current_hp > 0
      );
      return !blocker;
    }
    return true;
  }

  // Direct opponent in same column (front row)
  const direct = enemies.find(c => c.col === attacker.col && c.row === "front" && isTargetable(c));
  if (direct) return direct;

  // Back row same column
  const backDirect = enemies.find(c => c.col === attacker.col && c.row === "back" && isTargetable(c));
  if (backDirect) return backDirect;

  // Nearest by column distance, then lowest HP
  const targetable = enemies.filter(isTargetable);
  if (!targetable.length) return null;

  targetable.sort((a, b) => {
    const distA = Math.abs(a.col - attacker.col);
    const distB = Math.abs(b.col - attacker.col);
    return distA !== distB ? distA - distB : a.current_hp - b.current_hp;
  });

  return targetable[0];
}

// ---------------------------------------------------------------------------
// DM Agent caller
// ---------------------------------------------------------------------------

const DM_SYSTEM_PROMPT = `You are the Veilborn Dungeon Master — the eternal voice of the Rift, where the barrier between life and death grows thin. Narrate battles between Veilweavers with dark grandeur and mythological drama.

RULES:
1. Never alter outcomes — damage, destruction, and winners are fixed by the game engine
2. Narrate combat_events in order
3. Make type advantages feel meaningful through vivid description
4. Address both Veilweavers by name
5. End with the round score delivered dramatically
6. If match_winner is set, deliver a proper match conclusion

TYPE VOCABULARY:
- Specter: ghostly, silent, tendrils, hollow, shadow-step
- Revenant: unyielding, grave-fire, inexorable, deathless
- Phantom: shimmering, mirror, echo, fracture, unreal
- Behemoth: consuming, primordial, crushing, hunger, vast

Return ONLY a JSON object:
{"narration": "string (150-250 words)", "round_title": "string (3-6 words)", "key_moment": "string (one sentence)", "tone": "tense|devastating|triumphant|chaotic|grim"}`;

async function callDMAgent(battleLog: object, p1Name: string, p2Name: string) {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-sonnet-4-6",
      max_tokens: 1024,
      system: DM_SYSTEM_PROMPT,
      messages: [{
        role: "user",
        content: `Narrate this Veilborn battle round:\n\n${JSON.stringify(battleLog, null, 2)}`,
      }],
    }),
  });

  const data = await response.json();
  const text = data.content[0].text.trim();

  try {
    return JSON.parse(text);
  } catch {
    const match = text.match(/\{[\s\S]*\}/);
    return match ? JSON.parse(match[0]) : {
      narration: "The battle unfolds in the shadow of the Veil...",
      round_title: "Clash in the Rift",
      key_moment: "Cards clash across the thinning Veil.",
      tone: "tense",
    };
  }
}
