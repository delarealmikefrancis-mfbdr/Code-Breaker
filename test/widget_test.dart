// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:code_breaker/game/game_engine.dart';
import 'package:code_breaker/game/game_session.dart';
import 'package:code_breaker/main.dart';

void main() {
  testWidgets('shows a loading screen while opening the saved game', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AppLoader());

    expect(find.byType(LoadingScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();

    expect(find.byType(GamePage), findsOneWidget);
    expect(find.text('Pick a code'), findsOneWidget);
    tester.widget<GamePage>(find.byType(GamePage)).session.togglePause();
  });

  testWidgets('tutorial leads into a playable game', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = await GameSession.restore();
    addTearDown(session.dispose);
    await tester.pumpWidget(CodeBreakerApp(session: session));
    await tester.pumpAndSettle();

    expect(find.text('Pick a code'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Let’s play'));
    await tester.pumpAndSettle();

    expect(find.text('STARTER'), findsOneWidget);
    expect(find.text('CHOOSE YOUR ANSWER'), findsOneWidget);
    session.togglePause();
    final pausedAt = session.elapsedSeconds;
    await tester.pump(const Duration(seconds: 3));
    expect(session.elapsedSeconds, pausedAt);
    session.togglePause();
    expect(find.byType(FilledButton), findsNWidgets(4));
    session.togglePause();
  });

  testWidgets('educational modes create fresh questions and accept an answer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final session = await GameSession.restore();
    addTearDown(session.dispose);
    final feedbackCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        feedbackCalls.add(call.method);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    session.tutorialSeen = true;
    session.startNewGame(nextMode: GameMode.starter);
    final firstStarterQuestion = session.quizChallenge!;
    session.startNewGame(nextMode: GameMode.starter);
    expect(
      session.quizChallenge!.numbers,
      isNot(equals(firstStarterQuestion.numbers)),
    );

    session.startNewGame(nextMode: GameMode.builder);
    expect(session.quizChallenge!.category, QuizCategory.code);
    session.startNewGame(nextMode: GameMode.percentage);
    expect(session.quizChallenge!.category, QuizCategory.percentage);
    final firstPercentageQuestion = session.quizChallenge!;
    session.startNewGame(nextMode: GameMode.starter);
    session.startNewGame(nextMode: GameMode.percentage);
    expect(
      session.quizChallenge!.numbers,
      isNot(equals(firstPercentageQuestion.numbers)),
    );

    await tester.pumpWidget(CodeBreakerApp(session: session));
    await tester.pumpAndSettle();
    expect(find.text('PERCENTAGE'), findsNWidgets(2));
    final answer = session.quizChallenge!.correctAnswer;
    final answerButton = find.widgetWithText(FilledButton, '$answer');
    await tester.ensureVisible(answerButton);
    await tester.tap(answerButton);
    await tester.pumpAndSettle();
    expect(session.isOver, isTrue);
    expect(session.isWon, isTrue);
    expect(find.text('Correct!'), findsOneWidget);
    expect(feedbackCalls, contains('HapticFeedback.vibrate'));
    expect(feedbackCalls, contains('SystemSound.play'));

    session.startNewGame();
    session.setSound(false);
    await tester.pumpAndSettle();
    final nextAnswer = session.quizChallenge!.correctAnswer;
    await tester.tap(find.widgetWithText(FilledButton, '$nextAnswer'));
    await tester.pumpAndSettle();
    expect(
      feedbackCalls
          .where((method) => method == 'HapticFeedback.vibrate')
          .length,
      2,
    );
    expect(
      feedbackCalls.where((method) => method == 'SystemSound.play').length,
      1,
    );

    session.startNewGame();
    session.setSound(true);
    session.setVibration(false);
    await tester.pumpAndSettle();
    final finalAnswer = session.quizChallenge!.correctAnswer;
    await tester.tap(find.widgetWithText(FilledButton, '$finalAnswer'));
    await tester.pumpAndSettle();
    expect(
      feedbackCalls
          .where((method) => method == 'HapticFeedback.vibrate')
          .length,
      2,
    );
    expect(
      feedbackCalls.where((method) => method == 'SystemSound.play').length,
      2,
    );
  });

  testWidgets('shows category-specific hints in the bottom footer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final session = await GameSession.restore();
    addTearDown(session.dispose);
    session.tutorialSeen = true;
    await tester.pumpWidget(CodeBreakerApp(session: session));
    await tester.pump();

    final examples = <(QuizCategory, List<int>, String)>[
      (
        QuizCategory.arithmetic,
        [8, 3],
        'The step is 3. Add it to the last term.',
      ),
      (QuizCategory.geometric, [2, 4], 'Each term is multiplied by 4.'),
      (
        QuizCategory.fibonacci,
        [1, 2],
        'Add the previous two terms to find the next one.',
      ),
      (
        QuizCategory.code,
        [5, 7],
        'Substitute both values, then evaluate the addition inside print.',
      ),
      (
        QuizCategory.percentage,
        [25, 80],
        'Multiply the number by the percent, then divide by 100.',
      ),
    ];
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    for (final (category, numbers, expectedHint) in examples) {
      session.quizChallenge = QuizChallenge(
        category: category,
        prompt: 'Question',
        options: const [1, 2, 3, 4],
        correctAnswer: 2,
        numbers: numbers,
      );
      session.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text(expectedHint), findsOneWidget);
      expect(
        tester.getRect(find.text(expectedHint)).bottom,
        lessThan(screenHeight),
      );
    }
    session.togglePause();
  });

  testWidgets('horizontal swipes change modes and slider changes difficulty', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final session = await GameSession.restore();
    addTearDown(session.dispose);
    session.tutorialSeen = true;
    await tester.pumpWidget(CodeBreakerApp(session: session));
    await tester.pump();

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1200);
    await tester.pumpAndSettle();
    expect(session.mode, GameMode.builder);

    await tester.drag(find.byType(Slider), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(session.difficulty, Difficulty.expert);
    session.togglePause();
  });

  testWidgets('reveals the answer after 50 active seconds', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = await GameSession.restore();
    addTearDown(session.dispose);
    session.tutorialSeen = true;
    await tester.pumpWidget(CodeBreakerApp(session: session));
    await tester.pump();

    await tester.pump(const Duration(seconds: 49));
    expect(session.isOver, isFalse);
    expect(session.remainingQuestionSeconds, 1);
    await tester.pump(const Duration(seconds: 1));

    expect(session.isOver, isTrue);
    expect(session.timedOut, isTrue);
    expect(session.remainingQuestionSeconds, 0);
    expect(find.text('Time is up'), findsOneWidget);
    expect(
      find.text('Answer: ${session.quizChallenge!.correctAnswer}'),
      findsOneWidget,
    );
  });

  test('retired mode saves migrate to Starter without losing stats', () async {
    for (final oldMode in ['classic', 'timed', 'daily', 'endless']) {
      SharedPreferences.setMockInitialValues({
        'code_breaker_session_v1': jsonEncode({
          'mode': oldMode,
          'difficulty': 'easy',
          'code': [0, 1, 2],
          'quizChallenge': null,
          'lastQuizChallenge': null,
          'guesses': [],
          'currentGuess': [null, null, null],
          'eliminatedSymbols': [],
          'revealedSlot': null,
          'elapsedSeconds': 12,
          'extraAttempts': 0,
          'powerUps': 2,
          'wins': 3,
          'losses': 1,
          'totalAttempts': 9,
          'winningAttempts': 8,
          'starsEarned': 5,
          'bestTimeSeconds': 40,
          'currentStreak': 1,
          'bestStreak': 3,
          'xp': 200,
          'gamesPlayed': 4,
          'soundEnabled': true,
          'vibrationEnabled': true,
          'darkTheme': false,
          'tutorialSeen': true,
          'languageCode': 'en',
          'themeId': 'field',
          'lastWinDate': null,
          'isOver': false,
          'isWon': false,
        }),
      });
      final session = await GameSession.restore();

      expect(session.mode, GameMode.starter);
      expect(session.quizChallenge, isNotNull);
      expect(session.wins, 3);
      expect(session.xp, 200);
      session.dispose();
    }
  });
}
