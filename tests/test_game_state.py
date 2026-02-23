"""Tests for GameState class"""
import pytest
import sys
sys.path.insert(0, '..')

from engine.game_state import GameState
from engine.player import Player
from engine.card import Card


def test_game_initialization():
    deck1 = [Card(i, f"Card {i}", "unit", 1, 1, 1) for i in range(10)]
    deck2 = [Card(i, f"Card {i}", "unit", 1, 1, 1) for i in range(10, 20)]
    
    p1 = Player(1, "Player 1", deck1)
    p2 = Player(2, "Player 2", deck2)
    
    game = GameState(p1, p2)
    game.start_game()
    
    assert len(p1.hand) == 3
    assert len(p2.hand) == 4


def test_next_turn():
    deck1 = [Card(i, f"Card {i}", "unit", 1, 1, 1) for i in range(10)]
    deck2 = [Card(i, f"Card {i}", "unit", 1, 1, 1) for i in range(10, 20)]
    
    p1 = Player(1, "Player 1", deck1)
    p2 = Player(2, "Player 2", deck2)
    
    game = GameState(p1, p2)
    game.start_game()
    
    initial_hand_size = len(p1.hand)
    game.next_turn()
    
    assert game.turn == 1
    assert len(p1.hand) == initial_hand_size + 1
    assert p1.max_mana == 2


def test_check_winner():
    p1 = Player(1, "Player 1", [])
    p2 = Player(2, "Player 2", [])
    
    game = GameState(p1, p2)
    
    assert game.check_winner() is None
    
    p2.health = 0
    winner = game.check_winner()
    assert winner == p1
