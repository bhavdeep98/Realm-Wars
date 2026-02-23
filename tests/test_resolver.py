"""Tests for TurnResolver class"""
import pytest
import sys
sys.path.insert(0, '..')

from engine.game_state import GameState
from engine.player import Player
from engine.card import Card
from engine.resolver import TurnResolver


def test_resolve_card_play():
    p1 = Player(1, "Player 1", [])
    p2 = Player(2, "Player 2", [])
    
    card = Card(1, "Test Unit", "unit", 2, 3, 2)
    p1.hand.append(card)
    p1.mana = 3
    
    game = GameState(p1, p2)
    resolver = TurnResolver(game)
    
    actions = [{'type': 'play_card', 'card': card}]
    results = resolver.resolve_turn(actions, [])
    
    assert len(results['p1_played']) == 1
    assert len(p1.field) == 1


def test_resolve_combat():
    p1 = Player(1, "Player 1", [])
    p2 = Player(2, "Player 2", [])
    
    attacker = Card(1, "Attacker", "unit", 2, 3, 2)
    p1.field.append(attacker)
    
    game = GameState(p1, p2)
    resolver = TurnResolver(game)
    
    p1_actions = [{'type': 'attack', 'attacker': attacker, 'target': None}]
    results = resolver.resolve_turn(p1_actions, [])
    
    assert p2.health == 27
    assert attacker.is_exhausted == True


def test_unit_vs_unit_combat():
    p1 = Player(1, "Player 1", [])
    p2 = Player(2, "Player 2", [])
    
    attacker = Card(1, "Attacker", "unit", 2, 4, 2)
    defender = Card(2, "Defender", "unit", 2, 2, 3)
    
    p1.field.append(attacker)
    p2.field.append(defender)
    
    game = GameState(p1, p2)
    resolver = TurnResolver(game)
    
    p1_actions = [{'type': 'attack', 'attacker': attacker, 'target': defender}]
    results = resolver.resolve_turn(p1_actions, [])
    
    assert len(results['combat']) == 1
    assert defender.defense == -1
    assert len(p2.field) == 0
