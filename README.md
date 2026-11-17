# Code-Breaker

A mobile logic puzzle built with Flutter and Dart for Android and iOS. The game works offline and stores the active round and player progress locally.

## Play

```powershell
flutter pub get
flutter run
```

## Modes and progression

- **Starter** asks arithmetic, geometric, and Fibonacci sequence questions.
- **Builder** asks basic code-output questions.
- **Percentage** asks percentage-of-a-number questions.
- New questions use different numbers, including after switching to another mode and back.
- Wins grant XP, stars, and streak progress. Tide and Ember themes unlock at levels 3 and 5.

Choose one of four answers for each question. Pause, help, settings, and stats are available in-game.

## Development

Game rules, duplicate-aware hint scoring, and question generation are in `lib/game/game_engine.dart`; local session state, timer, and persistence are in `lib/game/game_session.dart`.

```powershell
flutter test
flutter analyze
```