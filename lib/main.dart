import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/game_engine.dart';
import 'game/game_session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppLoader());
}

class AppLoader extends StatefulWidget {
  const AppLoader({super.key});

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> {
  late final Future<GameSession> _session = _loadSession();

  Future<GameSession> _loadSession() async {
    final session = await GameSession.restore();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return session;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<GameSession>(
    future: _session,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return CodeBreakerApp(session: snapshot.data!);
      }
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: LoadingScreen(),
      );
    },
  );
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F3ED),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/code_breaker_logo.png',
            width: min(MediaQuery.sizeOf(context).width * .82, 320),
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 18),
          const SizedBox(
            width: 110,
            child: LinearProgressIndicator(minHeight: 3),
          ),
        ],
      ),
    ),
  );
}

class CodeBreakerApp extends StatelessWidget {
  const CodeBreakerApp({super.key, required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) => MaterialApp(
      title: 'Code-Breaker',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(session.darkTheme, session.themeId),
      home: GamePage(session: session),
    ),
  );
}

ThemeData _buildTheme(bool dark, String themeId) {
  const ink = Color(0xFF202521);
  const paper = Color(0xFFF4F3ED);
  final (seed, accent) = switch (themeId) {
    'tide' => (const Color(0xFF267A78), const Color(0xFF83E0D0)),
    'ember' => (const Color(0xFFB64E36), const Color(0xFFFFB45C)),
    _ => (const Color(0xFF517A68), const Color(0xFFD8F36A)),
  };
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: dark ? Brightness.dark : Brightness.light,
    surface: dark ? ink : Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? ink : paper,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? ink : paper,
      foregroundColor: dark ? paper : ink,
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: accent,
        foregroundColor: ink,
        enableFeedback: false,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    textTheme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light)
        .textTheme
        .apply(bodyColor: dark ? paper : ink, displayColor: dark ? paper : ink),
  );
}

class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.session});

  final GameSession session;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  GameSession get game => widget.session;
  late final PageController _modePageController = PageController(
    initialPage: GameMode.values.indexOf(game.mode),
  );
  double? _difficultyPreview;

  String _text(String english, [String? spanish]) =>
      game.languageCode == 'es' ? (spanish ?? english) : english;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!game.tutorialSeen && mounted) _showTutorial();
    });
  }

  @override
  void dispose() {
    _modePageController.dispose();
    super.dispose();
  }

  Future<void> _feedback({bool success = false}) async {
    final effects = <Future<void>>[];
    if (game.vibrationEnabled) {
      effects.add(
        _playFeedbackSafely(
          success
              ? HapticFeedback.mediumImpact()
              : HapticFeedback.selectionClick(),
        ),
      );
    }
    if (game.soundEnabled) {
      effects.add(
        _playFeedbackSafely(
          SystemSound.play(
            success ? SystemSoundType.alert : SystemSoundType.click,
          ),
        ),
      );
    }
    await Future.wait(effects);
  }

  Future<void> _playFeedbackSafely(Future<void> effect) async {
    try {
      await effect;
    } on PlatformException {
      // Some platforms or device settings do not provide this feedback channel.
    } on MissingPluginException {
      // Keep the other feedback channel working when a platform plugin is absent.
    }
  }

  Future<void> _showTutorial() async {
    var page = 0;
    const steps = [
      ('Pick a code', 'Tap symbols to fill the row. Tap a peg to remove it.'),
      (
        'Read the clues',
        'Solid marks are exact matches. Outlined marks belong elsewhere.',
      ),
      (
        'Crack the pattern',
        'Use undo, hints, and pause. A win earns XP and a power-up.',
      ),
    ];
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            _text(
              steps[page].$1,
              const [
                'Elige un código',
                'Lee las pistas',
                'Descifra el patrón',
              ][page],
            ),
          ),
          content: Text(
            _text(
              steps[page].$2,
              const [
                'Toca símbolos para llenar la fila. Toca una pieza para quitarla.',
                'Las marcas sólidas son exactas. Las huecas están en otra posición.',
                'Usa deshacer, pistas y pausa. Una victoria otorga XP y una ayuda.',
              ][page],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (page == steps.length - 1) {
                  game.markTutorialSeen();
                  Navigator.pop(dialogContext);
                } else {
                  setDialogState(() => page++);
                }
              },
              child: Text(
                page == steps.length - 1
                    ? _text('Let’s play', 'Jugar')
                    : _text('Next', 'Siguiente'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showStats() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _text('YOUR RUN', 'TUS ESTADÍSTICAS'),
              style: _eyebrow(context),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _stat(
                  context,
                  '${game.winRate}%',
                  _text('win rate', 'victorias'),
                ),
                _stat(
                  context,
                  game.averageAttempts.toStringAsFixed(1),
                  _text('avg. attempts', 'intentos prom.'),
                ),
                _stat(
                  context,
                  _duration(game.bestTimeSeconds),
                  _text('best time', 'mejor tiempo'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              '${_text('Current streak', 'Racha actual')}: ${game.currentStreak}  ·  ${_text('Best', 'Récord')}: ${game.bestStreak}',
            ),
            const SizedBox(height: 8),
            Text(
              '${_text('Level', 'Nivel')} ${game.level}  ·  ${game.xp} XP  ·  ${_text('Games', 'Partidas')}: ${game.gamesPlayed}',
            ),
            Text(
              '${_text('Stars earned', 'Estrellas ganadas')}: ${game.starsEarned}',
            ),
            const Divider(height: 28),
            Text(_text('ACHIEVEMENTS', 'LOGROS'), style: _eyebrow(context)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _achievement(
                  context,
                  game.wins > 0,
                  _text('First break', 'Primera clave'),
                ),
                _achievement(
                  context,
                  game.currentStreak >= 3 || game.bestStreak >= 3,
                  _text('On a roll', 'Imparable'),
                ),
                _achievement(
                  context,
                  game.bestTimeSeconds > 0 && game.bestTimeSeconds <= 60,
                  _text('Quick thinker', 'Mente veloz'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _showSettings() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: AnimatedBuilder(
        animation: game,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: Text(_text('Dark theme', 'Tema oscuro')),
                value: game.darkTheme,
                onChanged: game.setDarkTheme,
              ),
              SwitchListTile(
                title: Text(_text('Sound effects', 'Efectos de sonido')),
                value: game.soundEnabled,
                onChanged: game.setSound,
              ),
              SwitchListTile(
                title: Text(_text('Vibration', 'Vibración')),
                value: game.vibrationEnabled,
                onChanged: game.setVibration,
              ),
              ListTile(
                title: Text(_text('Language', 'Idioma')),
                trailing: DropdownButton<String>(
                  value: game.languageCode,
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'es', child: Text('Español')),
                  ],
                  onChanged: (value) {
                    if (value != null) game.setLanguage(value);
                  },
                ),
              ),
              ListTile(
                title: Text(_text('Theme', 'Tema')),
                trailing: DropdownButton<String>(
                  value: game.themeId,
                  items: game.unlockedThemes
                      .map(
                        (theme) => DropdownMenuItem(
                          value: theme,
                          child: Text(_themeName(theme)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) game.setTheme(value);
                  },
                ),
              ),
              ListTile(
                title: Text(_text('Difficulty', 'Dificultad')),
                trailing: DropdownButton<Difficulty>(
                  value: game.difficulty,
                  items: Difficulty.values
                      .map(
                        (difficulty) => DropdownMenuItem(
                          value: difficulty,
                          child: Text(_difficultyName(difficulty)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) game.startNewGame(nextDifficulty: value);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _showOutcome() async {
    await _feedback(success: game.isWon);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          game.isWon
              ? _text('Code cracked!', '¡Código descifrado!')
              : _text('Out of tries', 'Sin intentos'),
        ),
        content: Text(
          game.isWon
              ? '${_text('You earned', 'Ganaste')} ${max(25, 100 - game.guesses.length * 8)} XP · ${_stars(game.guesses.length, game.elapsedSeconds)}'
              : '${_text('The code was', 'El código era')}  ${game.code.map((symbol) => GameEngine.symbols[symbol]).join('  ')}',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              game.startNewGame();
            },
            child: Text(_text('Play again', 'Otra partida')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: game,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const _BrandMark(),
        actions: [
          IconButton(
            tooltip: _text('How to play', 'Cómo jugar'),
            onPressed: _showTutorial,
            icon: const Icon(Icons.help_outline),
          ),
          IconButton(
            tooltip: _text('Statistics', 'Estadísticas'),
            onPressed: _showStats,
            icon: const Icon(Icons.insights_outlined),
          ),
          IconButton(
            tooltip: _text('Settings', 'Ajustes'),
            onPressed: _showSettings,
            icon: const Icon(Icons.tune),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final landscape = constraints.maxWidth > constraints.maxHeight;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: _buildGame(context, landscape),
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _buildGame(BuildContext context, bool landscape) {
    if (game.mode.isQuestionMode) {
      return Column(
        children: [
          _buildModeSelector(context),
          _buildDifficultySlider(context),
          Expanded(
            child: PageView.builder(
              controller: _modePageController,
              itemCount: GameMode.values.length,
              onPageChanged: _handleModePageChanged,
              itemBuilder: (context, index) {
                final mode = GameMode.values[index];
                if (mode == game.mode) {
                  return Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          key: ValueKey(mode),
                          child: _buildQuestionBoard(context),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: _questionHintCard(context, game.quizChallenge!),
                      ),
                    ],
                  );
                }
                return Center(
                  child: Text(
                    _questionModeTitle(mode),
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }
    if (landscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: SingleChildScrollView(child: _buildBoard(context))),
          const VerticalDivider(width: 1),
          SizedBox(
            width: 320,
            child: SingleChildScrollView(child: _buildControls(context)),
          ),
        ],
      );
    }
    return Column(
      children: [
        Expanded(child: SingleChildScrollView(child: _buildBoard(context))),
        const Divider(height: 1),
        _buildControls(context),
      ],
    );
  }

  Widget _buildModeSelector(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<GameMode>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: GameMode.starter,
            label: Text(_modeName(GameMode.starter)),
          ),
          ButtonSegment(
            value: GameMode.builder,
            label: Text(_modeName(GameMode.builder)),
          ),
          ButtonSegment(
            value: GameMode.percentage,
            label: Text(_modeName(GameMode.percentage)),
          ),
        ],
        selected: {game.mode},
        onSelectionChanged: (selection) {
          if (selection.isNotEmpty) _selectMode(selection.first);
        },
      ),
    ),
  );

  Widget _buildDifficultySlider(BuildContext context) {
    final value = _difficultyPreview ?? game.difficulty.index.toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _text('DIFFICULTY', 'DIFICULTAD'),
                  style: _eyebrow(context),
                ),
              ),
              Text(
                _difficultyName(Difficulty.values[value.round()]),
                style: _eyebrow(context),
              ),
            ],
          ),
          Slider(
            value: value,
            min: 0,
            max: (Difficulty.values.length - 1).toDouble(),
            divisions: Difficulty.values.length - 1,
            label: _difficultyName(Difficulty.values[value.round()]),
            onChanged: (next) => setState(() => _difficultyPreview = next),
            onChangeEnd: (next) {
              final difficulty = Difficulty.values[next.round()];
              setState(() => _difficultyPreview = null);
              if (difficulty != game.difficulty) {
                game.startNewGame(nextDifficulty: difficulty);
              }
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: Difficulty.values
                .map(
                  (difficulty) => Text(
                    _difficultyName(difficulty),
                    style: _eyebrow(context),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  void _selectMode(GameMode mode) {
    if (mode == game.mode) return;
    game.startNewGame(nextMode: mode);
    if (_modePageController.hasClients) {
      _modePageController.animateToPage(
        GameMode.values.indexOf(mode),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _handleModePageChanged(int index) {
    final mode = GameMode.values[index];
    if (mode != game.mode) game.startNewGame(nextMode: mode);
  }

  Widget _buildBoard(BuildContext context) {
    if (game.mode.isQuestionMode) return _buildQuestionBoard(context);
    final slotSize = min(
      54.0,
      (MediaQuery.sizeOf(context).width - 72) / game.rules.codeLength,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _text('BREAK THE CODE', 'DESCIFRA EL CÓDIGO'),
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton.filledTonal(
                tooltip: game.isPaused
                    ? _text('Resume', 'Continuar')
                    : _text('Pause', 'Pausa'),
                onPressed: game.isOver ? null : game.togglePause,
                icon: Icon(game.isPaused ? Icons.play_arrow : Icons.pause),
              ),
              const SizedBox(width: 6),
              _timerPill(context),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: [
                    _menuChip<GameMode>(
                      value: game.mode,
                      options: GameMode.values,
                      label: _modeName,
                      onSelected: (mode) => game.startNewGame(nextMode: mode),
                    ),
                    _menuChip<Difficulty>(
                      value: game.difficulty,
                      options: Difficulty.values,
                      label: _difficultyName,
                      onSelected: (difficulty) =>
                          game.startNewGame(nextDifficulty: difficulty),
                    ),
                  ],
                ),
              ),
              Text(
                '${_text('LV', 'NV')} ${game.level}',
                style: _eyebrow(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _text('ATTEMPTS', 'INTENTOS'),
                  style: _eyebrow(context),
                ),
              ),
              Text(
                '${game.guesses.length} / ${game.rules.attemptLimit + game.extraAttempts}',
                style: _eyebrow(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 5,
              value:
                  game.guesses.length /
                  (game.rules.attemptLimit + game.extraAttempts),
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
              color: const Color(0xFF93B851),
            ),
          ),
          const SizedBox(height: 10),
          ...game.guesses.asMap().entries.map(
            (entry) => _guessRow(context, entry.key, entry.value, slotSize),
          ),
          if (!game.isOver) _currentRow(context, slotSize),
          if (game.isPaused)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: Text(
                  _text('PAUSED', 'EN PAUSA'),
                  style: _eyebrow(context),
                ),
              ),
            ),
          if (game.isOver) _revealedCode(context, slotSize),
        ],
      ),
    );
  }

  Widget _buildQuestionBoard(BuildContext context) {
    final challenge = game.quizChallenge;
    if (challenge == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _questionModeTitle(game.mode),
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton.filledTonal(
                tooltip: game.isPaused
                    ? _text('Resume', 'Continuar')
                    : _text('Pause', 'Pausa'),
                onPressed: game.isOver ? null : game.togglePause,
                icon: Icon(game.isPaused ? Icons.play_arrow : Icons.pause),
              ),
              const SizedBox(width: 6),
              _timerPill(context),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_text('LEVEL', 'NIVEL')} ${game.level} · ${_questionCategory(challenge.category)}',
            style: _eyebrow(context),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _questionCategory(challenge.category),
                  style: _eyebrow(context),
                ),
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    challenge.prompt,
                    key: ValueKey(challenge.prompt),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFamily: challenge.category == QuizCategory.code
                          ? 'monospace'
                          : null,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (game.isOver)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: game.isWon
                    ? const Color(0xFFD8F36A)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.isWon
                        ? _text('Correct!', '¡Correcto!')
                        : game.timedOut
                        ? _text('Time is up', 'Se acabó el tiempo')
                        : _text('Not quite', 'Casi'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_text('Answer', 'Respuesta')}: ${challenge.correctAnswer}',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => game.startNewGame(),
                    icon: const Icon(Icons.refresh),
                    label: Text(_text('Next question', 'Siguiente pregunta')),
                  ),
                ],
              ),
            )
          else ...[
            Text(
              _text('CHOOSE YOUR ANSWER', 'ELIGE TU RESPUESTA'),
              style: _eyebrow(context),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: challenge.options
                      .map(
                        (answer) => SizedBox(
                          width: width,
                          height: 60,
                          child: FilledButton(
                            onPressed: game.isPaused
                                ? null
                                : () async {
                                    if (game.submitAnswer(answer)) {
                                      await _feedback(success: game.isWon);
                                    }
                                  },
                            child: Text(
                              '$answer',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
          if (game.isPaused && !game.isOver)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _text('PAUSED', 'EN PAUSA'),
                style: _eyebrow(context),
              ),
            ),
          if (game.xp > 0)
            Row(
              children: [
                Text('XP', style: _eyebrow(context)),
                const SizedBox(width: 8),
                Expanded(
                  child: LinearProgressIndicator(
                    value: game.levelProgress / 100,
                    minHeight: 4,
                  ),
                ),
                const SizedBox(width: 8),
                Text('${game.levelProgress}/100', style: _eyebrow(context)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _timerPill(BuildContext context) {
    final seconds = game.remainingQuestionSeconds;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 17),
          const SizedBox(width: 6),
          Text(
            _duration(seconds),
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _questionHintCard(BuildContext context, QuizChallenge challenge) {
    final (title, hint) = switch (challenge.category) {
      QuizCategory.arithmetic => (
        _text('Arithmetic hint', 'Pista aritmética'),
        _text(
          'The step is ${challenge.numbers[1]}. Add it to the last term.',
          'El salto es ${challenge.numbers[1]}. Súmalo al último término.',
        ),
      ),
      QuizCategory.geometric => (
        _text('Geometric hint', 'Pista geométrica'),
        _text(
          'Each term is multiplied by ${challenge.numbers[1]}.',
          'Cada término se multiplica por ${challenge.numbers[1]}.',
        ),
      ),
      QuizCategory.fibonacci => (
        _text('Fibonacci hint', 'Pista Fibonacci'),
        _text(
          'Add the previous two terms to find the next one.',
          'Suma los dos términos anteriores para hallar el siguiente.',
        ),
      ),
      QuizCategory.code => (
        _text('Code hint', 'Pista de código'),
        _text(
          'Substitute both values, then evaluate the addition inside print.',
          'Sustituye ambos valores y suma dentro de print.',
        ),
      ),
      QuizCategory.percentage => (
        _text('Percentage hint', 'Pista de porcentaje'),
        _text(
          'Multiply the number by the percent, then divide by 100.',
          'Multiplica el número por el porcentaje y divide entre 100.',
        ),
      ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _eyebrow(context)),
                const SizedBox(height: 4),
                Text(hint),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuChip<T>({
    required T value,
    required List<T> options,
    required String Function(T) label,
    required ValueChanged<T> onSelected,
  }) => PopupMenuButton<T>(
    onSelected: onSelected,
    itemBuilder: (context) => options
        .map(
          (option) => PopupMenuItem(value: option, child: Text(label(option))),
        )
        .toList(),
    child: Chip(
      visualDensity: VisualDensity.compact,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Text(label(value)), const Icon(Icons.expand_more, size: 16)],
      ),
      side: BorderSide(color: Theme.of(context).dividerColor),
    ),
  );

  Widget _guessRow(
    BuildContext context,
    int index,
    GuessEntry entry,
    double size,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        SizedBox(
          width: 26,
          child: Text('${index + 1}'.padLeft(2, '0'), style: _eyebrow(context)),
        ),
        ...entry.symbols.map(
          (symbol) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _peg(symbol: symbol, size: size * .72),
          ),
        ),
        const Spacer(),
        _hintMarks(context, entry.hints),
      ],
    ),
  );

  Widget _currentRow(BuildContext context, double size) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(width: 26, child: Text('GO', style: _eyebrow(context))),
        ...List.generate(game.rules.codeLength, (slot) {
          final symbol = game.currentGuess[slot];
          final fixed = slot == game.revealedSlot;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Semantics(
              button: true,
              label: symbol == null
                  ? _text('Empty slot', 'Espacio vacío')
                  : _symbolName(symbol),
              child: InkWell(
                borderRadius: BorderRadius.circular(50),
                onTap: fixed ? null : () => game.clearSlot(slot),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: symbol == null
                      ? _emptyPeg(key: ValueKey('empty$slot'), size: size)
                      : _peg(
                          key: ValueKey('$slot-$symbol'),
                          symbol: symbol,
                          size: size,
                          locked: fixed,
                        ),
                ),
              ),
            ),
          );
        }),
        const Spacer(),
        IconButton(
          tooltip: _text('Submit guess', 'Enviar intento'),
          onPressed:
              game.isPaused || game.currentGuess.any((symbol) => symbol == null)
              ? null
              : () async {
                  if (game.submitGuess()) {
                    if (game.isOver) {
                      _showOutcome();
                    } else {
                      await _feedback();
                    }
                  }
                },
          icon: const Icon(Icons.arrow_forward_rounded),
        ),
      ],
    ),
  );

  Widget _emptyPeg({Key? key, required double size}) => Container(
    key: key,
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: Theme.of(context).dividerColor, width: 1.5),
    ),
  );

  Widget _peg({
    Key? key,
    required int symbol,
    required double size,
    bool locked = false,
  }) => AnimatedScale(
    key: key,
    scale: 1,
    duration: const Duration(milliseconds: 160),
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _symbolColor(symbol).withValues(alpha: .14),
        border: Border.all(
          color: _symbolColor(symbol),
          width: locked ? 2.5 : 1.6,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        GameEngine.symbols[symbol],
        style: TextStyle(
          color: _symbolColor(symbol),
          fontSize: size * .52,
          height: 1,
        ),
      ),
    ),
  );

  Widget _hintMarks(BuildContext context, HintResult hints) => Semantics(
    label:
        '${hints.exact} ${_text('exact', 'exactas')}, ${hints.misplaced} ${_text('misplaced', 'mal colocadas')}',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(hints.exact, (_) => const _HintDot(exact: true)),
        ...List.generate(hints.misplaced, (_) => const _HintDot(exact: false)),
      ],
    ),
  );

  Widget _revealedCode(BuildContext context, double size) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(_text('CODE', 'CLAVE'), style: _eyebrow(context)),
        ),
        ...game.code.map(
          (symbol) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _peg(symbol: symbol, size: size * .72),
          ),
        ),
      ],
    ),
  );

  Widget _buildControls(BuildContext context) {
    if (game.mode.isQuestionMode) return const SizedBox.shrink();
    final disabled = game.isPaused || game.isOver;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _text('CHOOSE A SYMBOL', 'ELIGE UN SÍMBOLO'),
                  style: _eyebrow(context),
                ),
              ),
              IconButton(
                tooltip: _text('Undo', 'Deshacer'),
                onPressed: disabled ? null : game.undo,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: _text('Clear row', 'Limpiar fila'),
                onPressed: disabled ? null : game.clearRow,
                icon: const Icon(Icons.backspace_outlined),
              ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: List.generate(game.rules.symbolCount, (symbol) {
              final removed = game.eliminatedSymbols.contains(symbol);
              return SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  tooltip: _symbolName(symbol),
                  onPressed: disabled || removed
                      ? null
                      : () async {
                          game.placeSymbol(symbol);
                          await _feedback();
                        },
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    foregroundColor: _symbolColor(symbol),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  icon: Text(
                    GameEngine.symbols[symbol],
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_text('POWER-UPS', 'AYUDAS')}  ${game.powerUps}',
                  style: _eyebrow(context),
                ),
              ),
              _powerUpButton(
                Icons.visibility_outlined,
                _text('Reveal a slot', 'Revelar espacio'),
                !disabled && game.powerUps > 0,
                game.revealSlot,
              ),
              _powerUpButton(
                Icons.remove_circle_outline,
                _text('Eliminate a symbol', 'Eliminar símbolo'),
                !disabled && game.powerUps > 0,
                game.eliminateSymbol,
              ),
              _powerUpButton(
                Icons.add_circle_outline,
                _text('Extra attempt', 'Intento extra'),
                !disabled && game.powerUps > 0,
                game.earnExtraAttempt,
              ),
            ],
          ),
          if (game.xp > 0)
            Row(
              children: [
                Text('XP', style: _eyebrow(context)),
                const SizedBox(width: 8),
                Expanded(
                  child: LinearProgressIndicator(
                    value: game.levelProgress / 100,
                    minHeight: 4,
                  ),
                ),
                const SizedBox(width: 8),
                Text('${game.levelProgress}/100', style: _eyebrow(context)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _powerUpButton(
    IconData icon,
    String label,
    bool enabled,
    bool Function() action,
  ) => IconButton(
    tooltip: label,
    onPressed: enabled
        ? () async {
            if (action()) await _feedback();
          }
        : null,
    icon: Icon(icon),
  );

  String _modeName(GameMode mode) => switch (mode) {
    GameMode.starter => _text('Starter', 'Inicial'),
    GameMode.builder => _text('Builder', 'Constructor'),
    GameMode.percentage => _text('Percentage', 'Porcentaje'),
  };

  String _questionModeTitle(GameMode mode) => switch (mode) {
    GameMode.starter => _text('STARTER', 'INICIAL'),
    GameMode.builder => _text('BUILDER', 'CONSTRUCTOR'),
    GameMode.percentage => _text('PERCENTAGE', 'PORCENTAJE'),
  };

  String _questionCategory(QuizCategory category) => switch (category) {
    QuizCategory.arithmetic => _text(
      'ARITHMETIC SEQUENCE',
      'SECUENCIA ARITMÉTICA',
    ),
    QuizCategory.geometric => _text(
      'GEOMETRIC SEQUENCE',
      'SECUENCIA GEOMÉTRICA',
    ),
    QuizCategory.fibonacci => _text(
      'FIBONACCI SEQUENCE',
      'SECUENCIA FIBONACCI',
    ),
    QuizCategory.code => _text('CODE OUTPUT', 'RESULTADO DEL CÓDIGO'),
    QuizCategory.percentage => _text('PERCENTAGE', 'PORCENTAJE'),
  };

  String _difficultyName(Difficulty difficulty) => switch (difficulty) {
    Difficulty.easy => _text('Easy', 'Fácil'),
    Difficulty.medium => _text('Medium', 'Medio'),
    Difficulty.hard => _text('Hard', 'Difícil'),
    Difficulty.expert => _text('Expert', 'Experto'),
  };

  String _themeName(String theme) => switch (theme) {
    'tide' => _text('Tide', 'Marea'),
    'ember' => _text('Ember', 'Brasa'),
    _ => _text('Field', 'Campo'),
  };

  String _symbolName(int symbol) => switch (symbol) {
    0 => _text('Circle', 'Círculo'),
    1 => _text('Diamond', 'Rombo'),
    2 => _text('Triangle', 'Triángulo'),
    3 => _text('Square', 'Cuadrado'),
    4 => _text('Star', 'Estrella'),
    5 => _text('Plus', 'Más'),
    6 => _text('Hexagon', 'Hexágono'),
    _ => _text('Heart', 'Corazón'),
  };
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Image.asset(
        'assets/code_breaker_mark.png',
        width: 34,
        height: 34,
        fit: BoxFit.contain,
      ),
      const SizedBox(width: 9),
      const Text(
        'CODE-BREAKER',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    ],
  );
}

class _HintDot extends StatelessWidget {
  const _HintDot({required this.exact});

  final bool exact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: exact ? const Color(0xFF41664F) : Colors.transparent,
        border: Border.all(color: const Color(0xFF41664F), width: 1.5),
      ),
    ),
  );
}

TextStyle _eyebrow(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall!.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

Color _symbolColor(int symbol) => const [
  Color(0xFF2878A8),
  Color(0xFFC44E36),
  Color(0xFF718C25),
  Color(0xFF795B9B),
  Color(0xFFB77816),
  Color(0xFF347F72),
  Color(0xFFB44975),
  Color(0xFF58616D),
][symbol];

Widget _stat(BuildContext context, String value, String label) => Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w900),
      ),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  ),
);

Widget _achievement(BuildContext context, bool unlocked, String label) => Chip(
  avatar: Icon(unlocked ? Icons.check_circle : Icons.lock_outline, size: 17),
  label: Text(label, style: const TextStyle(fontSize: 12)),
  backgroundColor: unlocked
      ? const Color(0xFFD8F36A)
      : Theme.of(context).colorScheme.surfaceContainerHighest,
  side: BorderSide.none,
);

String _stars(int attempts, int seconds) =>
    '★' * starsForWin(attempts, seconds);

String _duration(int seconds) {
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}
