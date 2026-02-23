"""Card class for Realm Wars"""

class Card:
    def __init__(self, card_id, name, card_type, cost, attack=0, defense=0, effect=None):
        self.id = card_id
        self.name = name
        self.type = card_type  # 'unit', 'spell', 'structure'
        self.cost = cost
        self.attack = attack
        self.defense = defense
        self.effect = effect or {}
        self.is_exhausted = False
        
    def __repr__(self):
        return f"Card({self.name}, ATK:{self.attack}, DEF:{self.defense})"
    
    def can_attack(self):
        return self.type == 'unit' and not self.is_exhausted and self.attack > 0
    
    def exhaust(self):
        self.is_exhausted = True
    
    def refresh(self):
        self.is_exhausted = False
