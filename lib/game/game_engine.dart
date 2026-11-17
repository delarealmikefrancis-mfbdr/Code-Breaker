import 'dart:math';

enum GameMode { starter, builder, percentage }

extension GameModeQuestions on GameMode {
  bool get isQuestionMode =>
      this == GameMode.starter ||
      this == GameMode.builder ||
      this == GameMode.percentage;
}

enum QuizCategory { arithmetic, geometric, fibonacci, code, percentage }

class QuizChallenge {
  const QuizChallenge({
    required this.category,
    required this.prompt,
    required this.options,
    required this.correctAnswer,
    required this.numbers,
  });

  final QuizCategory category;
  final String prompt;
  final List<int> options;
  final int correctAnswer;
  final List<int> numbers;

  Map<String, Object> toJson() => {
    'category': category.name,
    'prompt': prompt,
    'options': options,
    'correctAnswer': correctAnswer,
    'numbers': numbers,
  };

  factory QuizChallenge.fromJson(Map<String, dynamic> json) => QuizChallenge(
    category: QuizCategory.values.byName(json['category'] as String),
    prompt: json['prompt'] as String,
    options: (json['options'] as List).cast<int>(),
    correctAnswer: json['correctAnswer'] as int,
    numbers: (json['numbers'] as List).cast<int>(),
  );
}

enum Difficulty { easy, medium, hard, expert }

class GameRules {
  const GameRules({
    required this.codeLength,
    required this.symbolCount,
    required this.attemptLimit,
    required this.allowRepeats,
  });

  final int codeLength;
  final int symbolCount;
  final int attemptLimit;
  final bool allowRepeats;

  factory GameRules.forDifficulty(Difficulty difficulty) {
    return switch (difficulty) {
      Difficulty.easy => const GameRules(
        codeLength: 3,
        symbolCount: 4,
        attemptLimit: 10,
        allowRepeats: false,
      ),
      Difficulty.medium => const GameRules(
        codeLength: 4,
        symbolCount: 6,
        attemptLimit: 9,
        allowRepeats: false,
      ),
      Difficulty.hard => const GameRules(
        codeLength: 5,
        symbolCount: 7,
        attemptLimit: 8,
        allowRepeats: true,
      ),
      Difficulty.expert => const GameRules(
        codeLength: 6,
        symbolCount: 8,
        attemptLimit: 7,
        allowRepeats: true,
      ),
    };
  }
}

class HintResult {
  const HintResult({required this.exact, required this.misplaced});

  final int exact;
  final int misplaced;

  bool get isSolved => exact > 0 && exact == exact + misplaced;
}

class GameEngine {
  static const symbols = <String>['●', '◆', '▲', '■', '★', '✚', '⬟', '♥'];

  static QuizChallenge generateChallenge(
    GameMode mode, {
    Random? random,
    QuizChallenge? previous,
  }) {
    if (!mode.isQuestionMode) {
      throw ArgumentError.value(mode, 'mode', 'Must be a question mode.');
    }
    final source = random ?? Random();
    var challenge = _createChallenge(mode, source);
    var retries = 0;
    while (previous != null &&
        (challenge.prompt == previous.prompt ||
            _sameNumbers(challenge.numbers, previous.numbers)) &&
        retries < 100) {
      challenge = _createChallenge(mode, source);
      retries++;
    }
    return challenge;
  }

  static QuizChallenge _createChallenge(GameMode mode, Random random) {
    late QuizCategory category;
    late String prompt;
    late int answer;
    late List<int> numbers;

    switch (mode) {
      case GameMode.starter:
        category = QuizCategory.values[random.nextInt(3)];
        if (category == QuizCategory.arithmetic) {
          final start = random.nextInt(15) + 2;
          final step = random.nextInt(8) + 2;
          numbers = [start, step];
          final sequence = List.generate(4, (index) => start + step * index);
          answer = sequence.last + step;
          prompt = '${sequence.join(', ')}, ?';
        } else if (category == QuizCategory.geometric) {
          final start = random.nextInt(6) + 1;
          final ratio = random.nextInt(3) + 2;
          numbers = [start, ratio];
          final sequence = List.generate(
            4,
            (index) => start * pow(ratio, index).toInt(),
          );
          answer = sequence.last * ratio;
          prompt = '${sequence.join(', ')}, ?';
        } else {
          final first = random.nextInt(7) + 1;
          final second = random.nextInt(7) + 1;
          numbers = [first, second];
          final sequence = [first, second];
          while (sequence.length < 5) {
            sequence.add(
              sequence[sequence.length - 1] + sequence[sequence.length - 2],
            );
          }
          answer = sequence.last + sequence[sequence.length - 2];
          prompt = '${sequence.join(', ')}, ?';
        }
        break;
      case GameMode.builder:
        category = QuizCategory.code;
        final count = random.nextInt(18) + 2;
        final bonus = random.nextInt(18) + 2;
        numbers = [count, bonus];
        answer = count + bonus;
        prompt =
            'What does this code print?\n\ncount = $count\nbonus = $bonus\nprint(count + bonus)';
        break;
      case GameMode.percentage:
        category = QuizCategory.percentage;
        const percentages = [10, 20, 25, 50, 75];
        final percent = percentages[random.nextInt(percentages.length)];
        final whole = (random.nextInt(41) + 10) * 4;
        numbers = [percent, whole];
        answer = whole * percent ~/ 100;
        prompt = 'What is $percent% of $whole?';
        break;
    }

    final step = max(2, answer ~/ 8);
    final options = <int>{answer};
    for (final offset in [step, -step, step * 2, -step * 2, 1, -1]) {
      final candidate = answer + offset;
      if (candidate >= 0) options.add(candidate);
      if (options.length == 4) break;
    }
    while (options.length < 4) {
      options.add(answer + options.length * step + 1);
    }
    final shuffled = options.toList()..shuffle(random);
    return QuizChallenge(
      category: category,
      prompt: prompt,
      options: shuffled,
      correctAnswer: answer,
      numbers: numbers,
    );
  }

  static bool _sameNumbers(List<int> first, List<int> second) =>
      first.length == second.length &&
      List.generate(
        first.length,
        (index) => first[index] == second[index],
      ).every((same) => same);

  static HintResult calculateHints(List<int> code, List<int> guess) {
    if (code.length != guess.length) {
      throw ArgumentError('Code and guess must have the same length.');
    }

    var exact = 0;
    final remainingCode = <int, int>{};
    final remainingGuess = <int, int>{};

    for (var index = 0; index < code.length; index++) {
      if (code[index] == guess[index]) {
        exact++;
      } else {
        remainingCode.update(
          code[index],
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        remainingGuess.update(
          guess[index],
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }

    var misplaced = 0;
    for (final entry in remainingGuess.entries) {
      misplaced += min(entry.value, remainingCode[entry.key] ?? 0);
    }
    return HintResult(exact: exact, misplaced: misplaced);
  }

  static List<int> generateCode(GameRules rules, {Random? random}) {
    final source = random ?? Random();
    if (rules.allowRepeats) {
      return List<int>.generate(
        rules.codeLength,
        (_) => source.nextInt(rules.symbolCount),
      );
    }

    final available = List<int>.generate(rules.symbolCount, (index) => index)
      ..shuffle(source);
    return available.take(rules.codeLength).toList();
  }
}
