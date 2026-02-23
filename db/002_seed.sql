-- =============================================================================
-- VEILBORN — Seed Data
-- Run after 001_schema.sql
-- Seeds: card definitions, card packs, battle pass season 1
-- =============================================================================


-- ---------------------------------------------------------------------------
-- Card Definitions (matches data/cards.py exactly)
-- ---------------------------------------------------------------------------

insert into public.card_definitions
  (id, name, card_type, rarity, base_attack, base_defense, speed, mana_cost,
   ability_trigger, ability_effect, ability_value, ability_desc,
   lore, pack_weight)
values

-- SPECTERS
('spec_001', 'Morthex the Hollow',   'Specter', 'Common', 6, 8, 8, 3,
 'on_attack', 'lifesteal', 0.30,
 'Drains 30% of damage dealt as vitality',
 'Once a court assassin, Morthex slipped through the Veil mid-kill and never fully returned.',
 100),

('spec_002', 'Veyra Silentblade',    'Specter', 'Rare', 9, 6, 10, 4,
 'passive', 'ghost_step', 1.00,
 'Once per match, ignores back-row protection',
 'She moves through stone and steel alike. The Veil is simply another wall to her.',
 40),

('spec_003', 'Ashling',              'Specter', 'Common', 5, 5, 7, 2,
 null, null, null, null,
 'A child who wandered too close to the Veil. Now she wanders forever.',
 100),

-- REVENANTS
('rev_001', 'Gravaul the Unyielding','Revenant', 'Rare', 7, 14, 3, 4,
 'passive', 'armor', 2.00,
 'Reduces all incoming damage by 2',
 'Gravaul has died eleven times. He finds it less concerning each time.',
 40),

('rev_002', 'Serath the Unburied',   'Revenant', 'Common', 8, 10, 4, 3,
 'on_survive_round', 'last_stand', 3.00,
 'Gains +3 attack when below 50% HP',
 'The more Serath bleeds, the more dangerous he becomes.',
 100),

('rev_003', 'Duskwarden',            'Revenant', 'Common', 6, 12, 2, 3,
 null, null, null, null,
 'A sentinel of the Veil''s edge. Patient, immovable, inevitable.',
 100),

-- PHANTOMS
('phan_001', 'Mirrex',               'Phantom', 'Epic', 7, 7, 6, 5,
 'on_attack', 'thorns', 0.50,
 'Attacker takes 50% of damage dealt back as reflection',
 'Mirrex shows you your own destruction. Then makes it real.',
 15),

('phan_002', 'The Lurking Shade',    'Phantom', 'Common', 5, 6, 5, 2,
 null, null, null, null,
 'It has no name because it has no substance. It simply is, and then isn''t.',
 100),

('phan_003', 'Veilborn Trickster',   'Phantom', 'Rare', 8, 5, 9, 4,
 'passive', 'last_stand', 4.00,
 'Gains +4 attack when below 50% HP',
 'The Trickster is most dangerous when cornered. Don''t corner it.',
 40),

-- BEHEMOTHS
('beh_001', 'Vorath the Consuming',  'Behemoth', 'Legendary', 12, 18, 1, 7,
 'on_death', 'veil_echo', 0.50,
 'On death, releases a death echo dealing half its attack to its killer',
 'When Vorath dies, the killing blow echoes back. Some victories aren''t worth the price.',
 5),

('beh_002', 'Bonecrag',              'Behemoth', 'Common', 9, 14, 2, 5,
 null, null, null, null,
 'A thing assembled from the bones of things that should not be.',
 100),

('beh_003', 'The Pale Hunger',       'Behemoth', 'Rare', 10, 12, 3, 6,
 'on_attack', 'lifesteal', 0.40,
 'Feeds on the vitality of those it strikes, healing 40% of damage dealt',
 'It is always hungry. It will always be hungry. Feed it and it only grows.',
 40);


-- ---------------------------------------------------------------------------
-- Card Packs
-- ---------------------------------------------------------------------------

insert into public.card_packs
  (id, name, description, cards_per_pack, shard_cost, crystal_cost,
   guaranteed_rarity, art_url, is_active)
values

('starter_pack', 'Starter Pack',
 'A balanced introduction to the Veilborn. Contains 5 cards across all types.',
 5, 500, null, 'Common',
 '', true),

('veil_pack', 'Veil Pack',
 'Draw from the depths of the Veil. Higher chance of Rare and Epic cards.',
 5, null, 100, 'Rare',
 '', true),

('dark_ritual_pack', 'Dark Ritual Pack',
 'A dangerous ritual drawing power from deep beyond the Veil. Guaranteed Epic or better.',
 5, null, 300, 'Epic',
 '', true);


-- ---------------------------------------------------------------------------
-- Battle Pass — Season 1
-- ---------------------------------------------------------------------------

insert into public.battle_pass
  (id, name, description, season_number, crystal_cost, starts_at, ends_at, reward_tiers)
values
(
  'season_1',
  'Season 1: The Veil Awakens',
  'The first season of Veilborn. Earn exclusive cards, shards, and cosmetics.',
  1,
  500,
  now(),
  now() + interval '90 days',
  '[
    {"tier": 1,  "xp_required": 0,    "reward_type": "shards",      "amount": 50,  "card_definition_id": null, "premium_only": false},
    {"tier": 2,  "xp_required": 100,  "reward_type": "card",        "amount": 1,   "card_definition_id": "spec_003", "premium_only": false},
    {"tier": 3,  "xp_required": 250,  "reward_type": "shards",      "amount": 100, "card_definition_id": null, "premium_only": false},
    {"tier": 4,  "xp_required": 400,  "reward_type": "card",        "amount": 1,   "card_definition_id": "rev_003", "premium_only": false},
    {"tier": 5,  "xp_required": 600,  "reward_type": "shards",      "amount": 150, "card_definition_id": null, "premium_only": true},
    {"tier": 6,  "xp_required": 850,  "reward_type": "card",        "amount": 1,   "card_definition_id": "phan_002", "premium_only": false},
    {"tier": 7,  "xp_required": 1100, "reward_type": "crystals",    "amount": 50,  "card_definition_id": null, "premium_only": true},
    {"tier": 8,  "xp_required": 1400, "reward_type": "card",        "amount": 1,   "card_definition_id": "rev_002", "premium_only": false},
    {"tier": 9,  "xp_required": 1750, "reward_type": "shards",      "amount": 200, "card_definition_id": null, "premium_only": true},
    {"tier": 10, "xp_required": 2100, "reward_type": "card",        "amount": 1,   "card_definition_id": "spec_001", "premium_only": false},
    {"tier": 15, "xp_required": 3500, "reward_type": "card",        "amount": 1,   "card_definition_id": "phan_001", "premium_only": true},
    {"tier": 20, "xp_required": 5000, "reward_type": "card",        "amount": 1,   "card_definition_id": "beh_001", "premium_only": true}
  ]'::jsonb
);
