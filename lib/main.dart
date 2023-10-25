import 'dart:math';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ScoreNotifier extends ChangeNotifier {
  int score = 0;
  bool isGameOver = false;
  set gameOver(bool state) {
    isGameOver = state;
    notifyListeners();
  }

  void setScore(int s) {
    score = s;
    notifyListeners();
  }
}

late ScoreNotifier scoreNotifier;

void main() {
  scoreNotifier = ScoreNotifier();
  WidgetsFlutterBinding.ensureInitialized();
  Flame.device.fullScreen();
  Flame.device.setLandscape();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: GameWidget(
          game: JumperGame(),
          overlayBuilderMap: {
            'hud': (BuildContext context, JumperGame game) {
              return Hud(game: game);
            },
          },
        ),
      ),
    ),
  );
}

class JumperGame extends FlameGame with TapCallbacks, HasCollisionDetection {
  late Player player;
  final _baseSpeed = 300;
  int charge = 0;
  bool isIdle = false;
  double _totalDt = 0;
  double _timeSinceBox = 0;
  int pressStartTime = 0;

  @override
  Future<void>? onLoad() async {
    player = Player();
    add(Sky());
    add(ScreenHitbox());
    add(player);
    add(Box(spawnX: 0));
    overlays.add('hud');
  }

  void gameover() {
    pauseEngine();
    scoreNotifier.gameOver = true;
  }

  void restart() {
    isIdle = false;
    _totalDt = 0;
    remove(player);
    player = Player();
    scoreNotifier.gameOver = false;
    scoreNotifier.setScore(0);
    onLoad();
    resumeEngine();
  }

  int get speed => _baseSpeed + charge * 2;
  int get totalDt => _totalDt.toInt();

  @override
  void update(double dt) {
    super.update(dt);
    if (!isIdle) {
      _timeSinceBox += dt;
      _totalDt += dt;
      if (_totalDt > scoreNotifier.score) {
        scoreNotifier.setScore(_totalDt.toInt());
      }
      _timeSinceBox += dt;
      if (_timeSinceBox > (10 / (12 + totalDt) + 1)) {
        add(Box());
        _timeSinceBox = 0;
      }
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    if (isIdle) {
      final pressEndTime = DateTime.now().millisecondsSinceEpoch;
      charge = min((pressEndTime - pressStartTime) ~/ 2, 450);
      player.jump();
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (isIdle) {
      pressStartTime = DateTime.now().millisecondsSinceEpoch;
    }
  }
}

class Player extends SpriteAnimationComponent
    with CollisionCallbacks, HasGameRef<JumperGame> {
  double acceleration = 1;
  Player() : super(size: Vector2(100, 100), position: Vector2(100, 100));

  EffectController e = EffectController(
    duration: 0.5,
    curve: Curves.decelerate,
  );

  @override
  Future<void>? onLoad() async {
    add(
      CircleHitbox(
        radius: 25,
        position: Vector2(25, 50),
      ),
    );
    final image = await Flame.images.load('slime.png');
    animation = SpriteAnimation.fromFrameData(
      image,
      SpriteAnimationData.sequenced(
        amount: 10,
        stepTime: 0.10,
        textureSize: Vector2.all(32),
      ),
    );
    flipHorizontally();
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    if (intersectionPoints.length == 2) {
      final mid =
          (intersectionPoints.elementAt(0) + intersectionPoints.elementAt(1)) /
              2;

      final collisionVector = absoluteCenter - mid;
      collisionVector.normalize();
      final isPlayerFallingDown = collisionVector.dot(Vector2(0, -1)) > 0.95;
      final isTopmostBoxSide = position.y < (other.y - 70);
      if (isPlayerFallingDown && isTopmostBoxSide && other is Box) {
        gameRef.isIdle = true;
        e.setToEnd();
        position.y = other.y - size.y;
      } else if (position.y > size.x && other is ScreenHitbox) {
        gameRef.gameover();
      }
    }
    super.onCollision(intersectionPoints, other);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!gameRef.isIdle && position.y < (game.size.y - 100)) {
      position.y += 350 * dt * acceleration;
      acceleration *= 1.04;
    }
  }

  void jump() {
    gameRef.isIdle = false;
    acceleration = 1;
    e = EffectController(
      duration: 0.3,
      curve: Curves.decelerate,
    );
    final effect =
        MoveByEffect(Vector2(0, -100 + (-gameRef.charge).toDouble()), e);
    add(effect);
  }
}

class Sky extends SpriteComponent {
  Sky() : super(priority: -1);

  @override
  Future<void>? onLoad() async {
    final skyImage = await Flame.images.load('sky.png');
    sprite = Sprite(skyImage);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }
}

class Box extends SpriteComponent with HasGameRef<JumperGame> {
  static Vector2 initialSize = Vector2.all(100);
  final double? spawnX;
  Box({this.spawnX}) : super();

  @override
  Future<void>? onLoad() async {
    final boxImage = await Flame.images.load('box.png');
    sprite = Sprite(boxImage);
    final randomFactor = Random().nextDouble() / 2 + 0.75;
    var width = (10 / (10 + gameRef.totalDt)) * 400 * randomFactor;
    width += spawnX != null ? 700 : 0;
    size = Vector2(width, gameRef.size.y / 4);
    position = Vector2(spawnX ?? gameRef.size.x, gameRef.size.y * 3 / 4);
    add(RectangleHitbox(isSolid: true));
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (position.x < -(Box.initialSize.x + 1200)) {
      removeFromParent();
    }
    if (!gameRef.isIdle) {
      position.x -= gameRef.speed * dt;
    }
  }
}

class Hud extends StatefulWidget {
  final JumperGame game;
  const Hud({required this.game, super.key});

  @override
  State<Hud> createState() => _HudState();
}

class _HudState extends State<Hud> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: scoreNotifier,
      child: Builder(
        builder: (context) {
          final p = Provider.of<ScoreNotifier>(context);
          return Stack(
            children: [
              if (p.isGameOver)
                Center(
                  child: Container(
                    color: const Color.fromARGB(255, 127, 208, 240),
                    height: 150,
                    width: 150,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'You scored ${p.score} !',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(
                          height: 16,
                        ),
                        IconButton(
                          onPressed: () => widget.game.restart(),
                          icon: const Icon(Icons.replay_outlined),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'Current score: ${p.score}',
                    style: const TextStyle(color: Colors.white, fontSize: 32),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
