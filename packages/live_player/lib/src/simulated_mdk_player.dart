import 'player_backend.dart';
import 'simulated_backend_player.dart';

class SimulatedMdkPlayer extends SimulatedBackendPlayer {
  SimulatedMdkPlayer()
      : super(
          backend: PlayerBackend.mdk,
          startupDelay: Duration(milliseconds: 40),
          bufferDelay: Duration(milliseconds: 30),
        );
}
