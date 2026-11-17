import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:code_breaker/game/game_engine.dart';

void main() {
  group('GameEngine.calculateHints', () {
    test('separates exact and misplaced symbols', () {
      final result = GameEngine.calculateHints([0, 1, 2, 3], [0, 2, 1, 4]);

      expect(result.exact, 1);
      expect(result.misplaced, 2);
    });

    test('does not overcount repeated guessed symbols', () {
      final result = GameEngine.calculateHints([0, 1, 2, 3], [0, 0, 0, 0]);

      expect(result.exact, 1);
      expect(result.misplaced, 0);
    });

    test('matches duplicate symbols only as many times as they occur', () {
      final result = GameEngine.calculateHints([0, 0, 1, 2], [0, 1, 0, 0]);

      expect(result.exact, 1);
      expect(result.misplaced, 2);
    });

    test('rejects guesses with a different length', () {
      expect(() => GameEngine.calculateHints([0, 1], [0]), throwsArgumentError);
    });
  });

  test('difficulty configures length, symbols, attempts, and repeats', () {
    final easy = GameRules.forDifficulty(Difficulty.easy);
    final expert = GameRules.forDifficulty(Difficulty.expert);

    expect(easy.codeLength, 3);
    expect(easy.allowRepeats, isFalse);
    expect(expert.codeLength, 6);
    expect(expert.symbolCount, 8);
    expect(expert.allowRepeats, isTrue);
  });

  test('starter generates arithmetic, geometric, and fibonacci questions', () {
    final categories = List.generate(
      120,
      (seed) => GameEngine.generateChallenge(
        GameMode.starter,
        random: Random(seed),
      ).category,
    ).toSet();

    expect(
      categories,
      containsAll([
        QuizCategory.arithmetic,
        QuizCategory.geometric,
        QuizCategory.fibonacci,
      ]),
    );
  });

  test('builder code-output and percentage answers are correct', () {
    final builder = GameEngine.generateChallenge(
      GameMode.builder,
      random: Random(4),
    );
    final percentage = GameEngine.generateChallenge(
      GameMode.percentage,
      random: Random(8),
    );

    expect(builder.category, QuizCategory.code);
    expect(builder.correctAnswer, builder.numbers[0] + builder.numbers[1]);
    expect(percentage.category, QuizCategory.percentage);
    expect(
      percentage.correctAnswer,
      percentage.numbers[1] * percentage.numbers[0] ~/ 100,
    );
    expect(builder.options, contains(builder.correctAnswer));
    expect(percentage.options, contains(percentage.correctAnswer));
  });

  test('a new question changes its numbers and survives serialization', () {
    final first = GameEngine.generateChallenge(
      GameMode.percentage,
      random: Random(12),
    );
    final next = GameEngine.generateChallenge(
      GameMode.percentage,
      random: Random(13),
      previous: first,
    );
    final restored = QuizChallenge.fromJson(next.toJson());

    expect(next.numbers, isNot(equals(first.numbers)));
    expect(restored.prompt, next.prompt);
    expect(restored.correctAnswer, next.correctAnswer);
  });

  test('only Starter, Builder, and Percentage are selectable modes', () {
    expect(GameMode.values, [
      GameMode.starter,
      GameMode.builder,
      GameMode.percentage,
    ]);
  });
}
