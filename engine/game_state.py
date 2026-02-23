"""Game state management for Realm Wars"""

class GameState:
    def __init__(self, player1, player2):
        self.player1 = player1
        self.player2 = player2
        self.turn = 0
        self.active_player = player1
        self.winner = None
        
    def start_game(self):
        """Initialize game by drawing starting hands"""
        self.player1.draw_card(3)
        self.player2.draw_card(4)
        
    def next_turn(self):
        """Advance to next turn"""
        self.turn += 1
        self.player1.start_turn()
        self.player2.start_turn()
        self.player1.draw_card()
        self.player2.draw_card()
        
    def check_winner(self):
        """Check if game has ended"""
        if self.player1.health <= 0:
            self.winner = self.player2
            return self.player2
        if self.player2.health <= 0:
            self.winner = self.player1
            return self.player1
        return None
    
    def get_opponent(self, player):
        """Get the opponent of given player"""
        return self.player2 if player == self.player1 else self.player1
