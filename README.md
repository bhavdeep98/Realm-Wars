# Realm Wars / Veilborn

A strategic card battler with simultaneous turn resolution and deep tactical gameplay.

## Project Structure

```
├── README.md              ← Project documentation
├── engine/                ← Python rules engine (10/10 tests passing)
├── data/                  ← 12 starter cards
├── tests/                 ← Test suite
├── db/                    ← Supabase schema, seed, edge function
├── simulate_match.py      ← Match simulator
└── veilborn_flutter/      ← Complete Flutter app
```

## Features

- Simultaneous turn resolution system
- Strategic card-based combat
- Python rules engine with comprehensive test coverage
- Flutter mobile app
- Supabase backend integration

## Getting Started

### Backend Setup

1. Set up Supabase project
2. Run schema from `db/schema.sql`
3. Seed initial data with `db/seed.sql`
4. Deploy edge function from `db/edge_function/`

### Engine Testing

```bash
cd engine
python -m pytest
```

### Match Simulation

```bash
python simulate_match.py
```

### Flutter App

```bash
cd veilborn_flutter
flutter pub get
flutter run
```

## Game Rules

Realm Wars features simultaneous turn resolution where both players select their actions, then all effects resolve in a specific order, creating deep strategic gameplay.

## License

MIT
