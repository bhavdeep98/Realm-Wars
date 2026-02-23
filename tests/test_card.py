"""Tests for Card class"""
import pytest
import sys
sys.path.insert(0, '..')

from engine.card import Card


def test_card_creation():
    card = Card(1, "Test Unit", "unit", 2, attack=3, defense=2)
    assert card.name == "Test Unit"
    assert card.cost == 2
    assert card.attack == 3
    assert card.defense == 2


def test_card_can_attack():
    card = Card(1, "Warrior", "unit", 2, attack=3, defense=2)
    assert card.can_attack() == True
    
    card.exhaust()
    assert card.can_attack() == False


def test_card_refresh():
    card = Card(1, "Warrior", "unit", 2, attack=3, defense=2)
    card.exhaust()
    assert card.is_exhausted == True
    
    card.refresh()
    assert card.is_exhausted == False
