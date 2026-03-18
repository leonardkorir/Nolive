import 'player_backend.dart';
import 'simulated_backend_player.dart';

class SimulatedMpvPlayer extends SimulatedBackendPlayer {
  SimulatedMpvPlayer()
      : super(
          backend: PlayerBackend.mpv,
          startupDelay: Duration(milliseconds: 60),
          bufferDelay: Duration(milliseconds: 40),
        );
}
