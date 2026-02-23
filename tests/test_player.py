"""Tests for Player class"""
import pytest
import sys
sys.path.insert(0, '..')

from engine.player import Player
from engine.card import Card


def test_player_creation():
    deck = [Card(i, f"Card {i}", "unit", 1, 1, 1) for i in range(10)]
    player = Player(1, "Test Player", deck)
    assert player.name == "Test Player"
    assert player.health == 30
    assert len(player.deck) == 10


def test_draw_card():
    deck = [Card(i, f"Card {i}", "unit", 1, 1, 1) for i in range(10)]
    player = Player(1, "Test Player", deck)
    
    drawn = player.draw_card(3)
    assert len(drawn) == 3
    assert len(player.hand) == 3
    assert len(player.deck) == 7


def test_play_card():
    card = Card(1, "Test Card", "unit", 2, 2, 2)
    player = Player(1, "Test Player", [])
    player.hand.append(card)
    player.mana = 3
    
    result = player.play_card(card)
    assert result == True
    assert len(player.hand) == 0
    assert len(player.field) == 1
    assert player.mana == 1


def test_take_damage():
    player = Player(1, "Test Player", [])
    is_dead = player.take_damage(10)
    assert player.health == 20
    assert is_dead == False
    
    is_dead = player.take_damage(25)
    assert player.health == -5
    assert is_dead == True
