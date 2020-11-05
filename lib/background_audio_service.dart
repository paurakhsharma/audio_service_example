import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_service_example/audio_screen.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

// This service runs in a seperate isolate
// changes made in this class will only take palce
// after the app is restarted
class BackgroundAudioService extends BackgroundAudioTask {
  AudioPlayer _player = new AudioPlayer();
  StreamSubscription<Duration> _postionSubscription;
  Duration _duration;
  List _tracks;

  @override
  Future<void> onStart(Map<String, dynamic> params) async {
    // We configure the audio session for speech since we're playing a devotion.
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.speech());

    _tracks = params['tracks'];

    print(_tracks);
    print(params['uri']);

    _duration = await _player.setUrl(
      params['uri'],
    );

    try {
      AudioServiceBackground.setQueue(_tracks
          .map<MediaItem>((e) => MediaItem(
                title: e['title'],
                album: 'Audio Test',
                id: e['id'].toString(),
              ))
          .toList());
    } catch (e) {
      print('error $e');
    }

    // Broadcast media item changes.
    // Propagate all events from the audio player to AudioService clients.
    _postionSubscription = _player.positionStream.listen((value) {
      _broadcastState();
    });

    onPlay();

    print('should be playing now');
  }

  @override
  Future<void> onPlay() => _player.play();

  @override
  Future<void> onPause() => _player.pause();

  @override
  Future<void> onSeekTo(Duration position) => _player.seek(position);

  @override
  Future<void> onSkipToNext() async => () {
        print('actual skip next pressed');
        final currentIndex = _getCurrentTrackIndex(_player.position);
        print(currentIndex);
        if (currentIndex < _tracks.length - 1) {
          _player.seek(
            Duration(milliseconds: _tracks[currentIndex + 1]['start']),
          );
        }
      };

  @override
  Future<void> onSkipToPrevious() async => () {
        print('actual skip to previous');
        final currentIndex = _getCurrentTrackIndex(_player.position);
        if (currentIndex > 0) {
          _player.seek(
            Duration(milliseconds: _tracks[currentIndex - 1]['start']),
          );
        }
      };

  @override
  Future<void> onSkipToQueueItem(index) async {
    print('skip to queue item called');
    // go to new track
    _player.seek(
      Duration(milliseconds: _tracks[int.parse(index)]['start']),
    );
  }

  @override
  Future<void> onStop() async {
    await _player.stop();
    await _player.dispose();
    _postionSubscription?.cancel();
    // It is important to wait for this state to be broadcast before we shut
    // down the task. If we don't, the background task will be destroyed before
    // the message gets sent to the UI.
    await _broadcastState();
    // Shut down this task
    await super.onStop();
  }

  /// Broadcasts the current state to all clients.
  Future<void> _broadcastState() async {
    final currentIndex = _getCurrentTrackIndex(_player.position);
    Map currentTrack;
    if (currentIndex > -1) {
      currentTrack = _tracks[currentIndex];
    }
    await AudioServiceBackground.setState(
      controls: [
        if (currentIndex > 0) MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        if (currentIndex < tracks.length - 1) MediaControl.skipToNext,
      ],
      systemActions: [
        MediaAction.seekTo,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        // tried uncommenting these as well
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.skipToQueueItem,
      ],
      processingState: _getProcessingState(),
      playing: _player.playing,
      position: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    );

    AudioServiceBackground.setMediaItem(
      MediaItem(
        id: currentTrack != null ? currentTrack['id'].toString() : '0',
        album: "Audio test album",
        title: currentTrack != null ? currentTrack['title'] : 'INTRODUCTION',
        artist: "Test user",
        duration: _duration,
      ),
    );
  }

  /// Maps just_audio's processing state into into audio_service's playing
  AudioProcessingState _getProcessingState() {
    switch (_player.processingState) {
      case ProcessingState.none:
        return AudioProcessingState.stopped;
      case ProcessingState.loading:
        return AudioProcessingState.connecting;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
      default:
        throw Exception("Invalid state: ${_player.processingState}");
    }
  }

  _getCurrentTrackIndex(Duration position) {
    return _tracks.lastIndexWhere(
      (element) => position.inMilliseconds > element['start'],
    );
  }
}
