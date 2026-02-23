"""Player class for Realm Wars"""

class Player:
    def __init__(self, player_id, name, deck):
        self.id = player_id
        self.name = name
        self.health = 30
        self.mana = 1
        self.max_mana = 1
        self.deck = deck[:]
        self.hand = []
        self.field = []
        self.discard = []
        
    def draw_card(self, count=1):
        drawn = []
        for _ in range(count):
            if self.deck:
                card = self.deck.pop(0)
                self.hand.append(card)
                drawn.append(card)
        return drawn
    
    def play_card(self, card):
        if card in self.hand and card.cost <= self.mana:
            self.hand.remove(card)
            self.mana -= card.cost
            if card.type in ['unit', 'structure']:
                self.field.append(card)
            else:
                self.discard.append(card)
            return True
        return False
    
    def take_damage(self, amount):
        self.health -= amount
        return self.health <= 0
    
    def start_turn(self):
        self.max_mana = min(self.max_mana + 1, 10)
        self.mana = self.max_mana
        for card in self.field:
            card.refresh()
