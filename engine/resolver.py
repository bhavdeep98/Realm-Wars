"""Turn resolver for simultaneous action resolution"""

class TurnResolver:
    def __init__(self, game_state):
        self.game = game_state
        
    def resolve_turn(self, p1_actions, p2_actions):
        """
        Resolve both players' actions simultaneously
        
        Resolution order:
        1. Play cards
        2. Activate abilities
        3. Combat
        4. End of turn effects
        """
        results = {
            'p1_played': [],
            'p2_played': [],
            'combat': [],
            'damage': {}
        }
        
        # Phase 1: Play cards
        for action in p1_actions:
            if action['type'] == 'play_card':
                card = action['card']
                if self.game.player1.play_card(card):
                    results['p1_played'].append(card)
        
        for action in p2_actions:
            if action['type'] == 'play_card':
                card = action['card']
                if self.game.player2.play_card(card):
                    results['p2_played'].append(card)
        
        # Phase 2: Combat
        p1_attacks = [a for a in p1_actions if a['type'] == 'attack']
        p2_attacks = [a for a in p2_actions if a['type'] == 'attack']
        
        combat_results = self._resolve_combat(p1_attacks, p2_attacks)
        results['combat'] = combat_results
        
        return results
    
    def _resolve_combat(self, p1_attacks, p2_attacks):
        """Resolve combat between attacking units"""
        combat_log = []
        
        for attack in p1_attacks:
            attacker = attack['attacker']
            target = attack.get('target')
            
            if target:
                # Unit vs unit
                attacker.exhaust()
                damage_dealt = max(0, attacker.attack - target.defense)
                target.defense -= attacker.attack
                
                if target.defense <= 0:
                    self.game.player2.field.remove(target)
                    self.game.player2.discard.append(target)
                    
                combat_log.append({
                    'attacker': attacker.name,
                    'target': target.name,
                    'damage': damage_dealt,
                    'destroyed': target.defense <= 0
                })
            else:
                # Direct attack
                attacker.exhaust()
                self.game.player2.take_damage(attacker.attack)
                combat_log.append({
                    'attacker': attacker.name,
                    'target': 'player',
                    'damage': attacker.attack
                })
        
        for attack in p2_attacks:
            attacker = attack['attacker']
            target = attack.get('target')
            
            if target:
                attacker.exhaust()
                damage_dealt = max(0, attacker.attack - target.defense)
                target.defense -= attacker.attack
                
                if target.defense <= 0:
                    self.game.player1.field.remove(target)
                    self.game.player1.discard.append(target)
                    
                combat_log.append({
                    'attacker': attacker.name,
                    'target': target.name,
                    'damage': damage_dealt,
                    'destroyed': target.defense <= 0
                })
            else:
                attacker.exhaust()
                self.game.player1.take_damage(attacker.attack)
                combat_log.append({
                    'attacker': attacker.name,
                    'target': 'player',
                    'damage': attacker.attack
                })
        
        return combat_log
