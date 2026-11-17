import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_engine.dart';

class GuessEntry {
  const GuessEntry({required this.symbols, required this.hints});

  final List<int> symbols;
  final HintResult hints;

  Map<String, Object> toJson() => {
    'symbols': symbols,
    'exact': hints.exact,
    'misplaced': hints.misplaced,
  };

  factory GuessEntry.fromJson(Map<String, dynamic> json) => GuessEntry(
    symbols: (json['symbols'] as List).cast<int>(),
    hints: HintResult(
      exact: json['exact'] as int,
      misplaced: json['misplaced'] as int,
    ),
  );
}

class GameSession extends ChangeNotifier {
  GameSession._();

  static const _storageKey = 'code_breaker_session_v1';
  static const questionTimeLimitSeconds = 50;

  GameMode mode = GameMode.starter;
  Difficulty difficulty = Difficulty.easy;
  GameRules rules = GameRules.forDifficulty(Difficulty.easy);
  List<int> code = [];
  QuizChallenge? quizChallenge;
  QuizChallenge? lastQuizChallenge;
  List<GuessEntry> guesses = [];
  List<int?> currentGuess = [];
  Set<int> eliminatedSymbols = {};
  int? revealedSlot;
  int elapsedSeconds = 0;
  int extraAttempts = 0;
  int powerUps = 2;
  int wins = 0;
  int losses = 0;
  int totalAttempts = 0;
  int winningAttempts = 0;
  int starsEarned = 0;
  int bestTimeSeconds = 0;
  int currentStreak = 0;
  int bestStreak = 0;
  int xp = 0;
  int level = 1;
  int gamesPlayed = 0;
  bool isPaused = false;
  bool isOver = false;
  bool isWon = false;
  bool timedOut = false;
  bool soundEnabled = true;
  bool vibrationEnabled = true;
  bool darkTheme = false;
  bool tutorialSeen = false;
  String languageCode = 'en';
  String themeId = 'field';
  String? _lastWinDate;
  Timer? _timer;
  SharedPreferences? _preferences;

  int get attemptsRemaining =>
      max(0, rules.attemptLimit + extraAttempts - guesses.length);
  int get levelProgress => xp % 100;
  int get winRate => gamesPlayed == 0 ? 0 : (wins * 100 ~/ gamesPlayed);
  double get averageAttempts => wins == 0 ? 0 : winningAttempts / wins;
  int get remainingQuestionSeconds =>
      max(0, questionTimeLimitSeconds - elapsedSeconds);
  List<String> get unlockedThemes => [
    'field',
    if (level >= 3) 'tide',
    if (level >= 5) 'ember',
  ];
  static Future<GameSession> restore() async {
    final session = GameSession._();
    session._preferences = await SharedPreferences.getInstance();
    final raw = session._preferences!.getString(_storageKey);
    if (raw != null) {
      try {
        session._restoreFromJson(jsonDecode(raw) as Map<String, dynamic>);
      } on Object {
        await session._preferences!.remove(_storageKey);
      }
    }
    if (session.quizChallenge == null) {
      session.startNewGame(nextMode: session.mode);
    } else if (!session.isOver) {
      session.isPaused = false;
      session._startTimer();
    }
    return session;
  }

  void startNewGame({GameMode? nextMode, Difficulty? nextDifficulty}) {
    mode = nextMode ?? mode;
    difficulty = nextDifficulty ?? difficulty;
    rules = GameRules.forDifficulty(difficulty);
    quizChallenge = GameEngine.generateChallenge(
      mode,
      previous: lastQuizChallenge,
    );
    lastQuizChallenge = quizChallenge;
    code = [];
    guesses = [];
    currentGuess = List<int?>.filled(rules.codeLength, null);
    eliminatedSymbols = {};
    revealedSlot = null;
    elapsedSeconds = 0;
    extraAttempts = 0;
    isPaused = false;
    isOver = false;
    isWon = false;
    timedOut = false;
    _timer?.cancel();
    _startTimer();
    _save();
    notifyListeners();
  }

  void placeSymbol(int symbol) {
    if (!_canPlay || eliminatedSymbols.contains(symbol)) return;
    final emptySlot = currentGuess.indexWhere((value) => value == null);
    if (emptySlot < 0) return;
    currentGuess[emptySlot] = symbol;
    _save();
    notifyListeners();
  }

  void clearSlot(int slot) {
    if (!_canPlay || slot < 0 || slot >= currentGuess.length) return;
    if (slot == revealedSlot) return;
    currentGuess[slot] = null;
    _save();
    notifyListeners();
  }

  void undo() {
    if (!_canPlay) return;
    for (var index = currentGuess.length - 1; index >= 0; index--) {
      if (currentGuess[index] != null && index != revealedSlot) {
        currentGuess[index] = null;
        break;
      }
    }
    _save();
    notifyListeners();
  }

  void clearRow() {
    if (!_canPlay) return;
    for (var index = 0; index < currentGuess.length; index++) {
      if (index != revealedSlot) currentGuess[index] = null;
    }
    _save();
    notifyListeners();
  }

  bool submitGuess() {
    if (!_canPlay || currentGuess.any((symbol) => symbol == null)) return false;
    final submitted = currentGuess.cast<int>();
    final hints = GameEngine.calculateHints(code, submitted);
    guesses.add(GuessEntry(symbols: [...submitted], hints: hints));
    totalAttempts++;
    final solved = hints.isSolved;
    if (solved) {
      _finish(true);
    } else if (attemptsRemaining == 0) {
      _finish(false);
    } else {
      currentGuess = List<int?>.filled(rules.codeLength, null);
      _save();
      notifyListeners();
    }
    return true;
  }

  bool submitAnswer(int answer) {
    if (!_canPlay ||
        !mode.isQuestionMode ||
        quizChallenge == null ||
        !quizChallenge!.options.contains(answer)) {
      return false;
    }
    totalAttempts++;
    _finish(answer == quizChallenge!.correctAnswer);
    return true;
  }

  bool revealSlot() {
    if (!_canPlay || powerUps == 0) return false;
    final candidates = List<int>.generate(
      code.length,
      (index) => index,
    ).where((index) => index != revealedSlot).toList();
    if (candidates.isEmpty) return false;
    final slot = candidates[Random().nextInt(candidates.length)];
    revealedSlot = slot;
    currentGuess[slot] = code[slot];
    powerUps--;
    _save();
    notifyListeners();
    return true;
  }

  bool eliminateSymbol() {
    if (!_canPlay || powerUps == 0) return false;
    final candidate = List<int>.generate(rules.symbolCount, (index) => index)
        .where(
          (symbol) =>
              !code.contains(symbol) && !eliminatedSymbols.contains(symbol),
        )
        .firstOrNull;
    if (candidate == null) return false;
    eliminatedSymbols.add(candidate);
    for (var slot = 0; slot < currentGuess.length; slot++) {
      if (currentGuess[slot] == candidate) currentGuess[slot] = null;
    }
    powerUps--;
    _save();
    notifyListeners();
    return true;
  }

  bool earnExtraAttempt() {
    if (!_canPlay || powerUps == 0) return false;
    powerUps--;
    extraAttempts++;
    _save();
    notifyListeners();
    return true;
  }

  void togglePause() {
    if (isOver) return;
    isPaused = !isPaused;
    if (isPaused) {
      _timer?.cancel();
    } else {
      _startTimer();
    }
    _save();
    notifyListeners();
  }

  void setSound(bool enabled) {
    soundEnabled = enabled;
    _save();
    notifyListeners();
  }

  void setVibration(bool enabled) {
    vibrationEnabled = enabled;
    _save();
    notifyListeners();
  }

  void setDarkTheme(bool enabled) {
    darkTheme = enabled;
    _save();
    notifyListeners();
  }

  void setLanguage(String language) {
    languageCode = language;
    _save();
    notifyListeners();
  }

  void setTheme(String theme) {
    if (unlockedThemes.contains(theme)) {
      themeId = theme;
      _save();
      notifyListeners();
    }
  }

  void markTutorialSeen() {
    tutorialSeen = true;
    _save();
  }

  bool get _canPlay =>
      !isPaused &&
      !isOver &&
      (mode.isQuestionMode ? quizChallenge != null : code.isNotEmpty);

  void _startTimer() {
    _timer?.cancel();
    if (isPaused || isOver) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsedSeconds++;
      if (elapsedSeconds >= questionTimeLimitSeconds) {
        timedOut = true;
        _finish(false);
      } else {
        _save();
        notifyListeners();
      }
    });
  }

  void _finish(bool won) {
    _timer?.cancel();
    isWon = won;
    isOver = true;
    gamesPlayed++;
    if (won) {
      final attempts = mode.isQuestionMode ? 1 : guesses.length;
      wins++;
      winningAttempts += attempts;
      starsEarned += starsForWin(attempts, elapsedSeconds);
      xp += max(25, 100 - attempts * 8);
      level = xp ~/ 100 + 1;
      powerUps++;
      if (bestTimeSeconds == 0 || elapsedSeconds < bestTimeSeconds) {
        bestTimeSeconds = elapsedSeconds;
      }
      final today = _dayKey(DateTime.now());
      final yesterday = _dayKey(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      currentStreak = _lastWinDate == today
          ? currentStreak
          : _lastWinDate == yesterday
          ? currentStreak + 1
          : 1;
      bestStreak = max(bestStreak, currentStreak);
      _lastWinDate = today;
    } else {
      losses++;
      currentStreak = 0;
    }
    _save();
    notifyListeners();
  }

  String _dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final preferences = _preferences;
    if (preferences == null) return;
    await preferences.setString(_storageKey, jsonEncode(_toJson()));
  }

  Map<String, Object?> _toJson() => {
    'mode': mode.name,
    'difficulty': difficulty.name,
    'code': code,
    'quizChallenge': quizChallenge?.toJson(),
    'lastQuizChallenge': lastQuizChallenge?.toJson(),
    'guesses': guesses.map((guess) => guess.toJson()).toList(),
    'currentGuess': currentGuess,
    'eliminatedSymbols': eliminatedSymbols.toList(),
    'revealedSlot': revealedSlot,
    'elapsedSeconds': elapsedSeconds,
    'extraAttempts': extraAttempts,
    'powerUps': powerUps,
    'wins': wins,
    'losses': losses,
    'totalAttempts': totalAttempts,
    'winningAttempts': winningAttempts,
    'starsEarned': starsEarned,
    'bestTimeSeconds': bestTimeSeconds,
    'currentStreak': currentStreak,
    'bestStreak': bestStreak,
    'xp': xp,
    'gamesPlayed': gamesPlayed,
    'soundEnabled': soundEnabled,
    'vibrationEnabled': vibrationEnabled,
    'darkTheme': darkTheme,
    'tutorialSeen': tutorialSeen,
    'languageCode': languageCode,
    'themeId': themeId,
    'lastWinDate': _lastWinDate,
    'isOver': isOver,
    'isWon': isWon,
    'timedOut': timedOut,
  };

  void _restoreFromJson(Map<String, dynamic> json) {
    final savedMode = json['mode'] as String?;
    mode = switch (savedMode) {
      'builder' => GameMode.builder,
      'percentage' || 'debugger' => GameMode.percentage,
      'starter' => GameMode.starter,
      _ => GameMode.starter,
    };
    difficulty = Difficulty.values.byName(json['difficulty'] as String);
    rules = GameRules.forDifficulty(difficulty);
    code = (json['code'] as List).cast<int>();
    final savedChallenge = json['quizChallenge'] as Map<String, dynamic>?;
    quizChallenge = savedChallenge == null
        ? null
        : QuizChallenge.fromJson(savedChallenge);
    final savedLastChallenge =
        json['lastQuizChallenge'] as Map<String, dynamic>?;
    lastQuizChallenge = savedLastChallenge == null
        ? quizChallenge
        : QuizChallenge.fromJson(savedLastChallenge);
    rules = GameRules.forDifficulty(difficulty);
    guesses = (json['guesses'] as List)
        .map((guess) => GuessEntry.fromJson(guess as Map<String, dynamic>))
        .toList();
    currentGuess = (json['currentGuess'] as List).cast<int?>();
    eliminatedSymbols = (json['eliminatedSymbols'] as List).cast<int>().toSet();
    revealedSlot = json['revealedSlot'] as int?;
    elapsedSeconds = json['elapsedSeconds'] as int;
    extraAttempts = json['extraAttempts'] as int;
    powerUps = json['powerUps'] as int;
    wins = json['wins'] as int;
    losses = json['losses'] as int;
    totalAttempts = json['totalAttempts'] as int;
    winningAttempts = json['winningAttempts'] as int? ?? 0;
    starsEarned = json['starsEarned'] as int? ?? 0;
    bestTimeSeconds = json['bestTimeSeconds'] as int;
    currentStreak = json['currentStreak'] as int;
    bestStreak = json['bestStreak'] as int;
    xp = json['xp'] as int;
    level = xp ~/ 100 + 1;
    gamesPlayed = json['gamesPlayed'] as int;
    soundEnabled = json['soundEnabled'] as bool;
    vibrationEnabled = json['vibrationEnabled'] as bool;
    darkTheme = json['darkTheme'] as bool;
    tutorialSeen = json['tutorialSeen'] as bool;
    languageCode = json['languageCode'] as String;
    themeId = json['themeId'] as String? ?? 'field';
    _lastWinDate = json['lastWinDate'] as String?;
    isOver = json['isOver'] as bool;
    isWon = json['isWon'] as bool;
    timedOut = json['timedOut'] as bool? ?? false;
    currentGuess = List<int?>.generate(
      rules.codeLength,
      (index) => index < currentGuess.length ? currentGuess[index] : null,
    );
    if (!unlockedThemes.contains(themeId)) themeId = 'field';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

int starsForWin(int attempts, int elapsedSeconds) {
  if (attempts <= 4 && elapsedSeconds <= 60) return 3;
  if (attempts <= 6 && elapsedSeconds <= 120) return 2;
  return 1;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
