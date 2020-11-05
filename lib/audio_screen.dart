import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

import 'background_audio_service.dart';

List tracks = [
  {"id": 1, "title": "INTRODUCTION", "start": 0},
  {"id": 2, "title": "2nd track", "start": 20347},
  {"id": 3, "title": "3rd track", "start": 50000},
  {"id": 4, "title": "4th track", "start": 70000},
];

class AudioScreen extends StatelessWidget {
  /// Tracks the position while the user drags the seek bar.
  final BehaviorSubject<double> _dragPositionSubject =
      BehaviorSubject.seeded(null);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Serv ice Demo'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<PlayerState>(
              stream: _playerStream,
              builder: (context, snapshot) {
                final screenState = snapshot.data;
                final mediaItem = screenState?.mediaItem;
                final state = screenState?.playbackState;
                final processingState =
                    state?.processingState ?? AudioProcessingState.none;
                final playing = state?.playing ?? false;

                final currentIndex = _getCurrentTrackIndex(
                  tracks,
                  state?.currentPosition ?? Duration(milliseconds: 0),
                );

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (currentIndex > 0 && playing)
                          previousButton(currentIndex - 1),
                        if (processingState == AudioProcessingState.completed)
                          rewindButton()
                        else if (playing)
                          pauseButton()
                        else
                          playButton(),
                        stopButton(),
                        if (currentIndex < tracks.length - 1 && playing)
                          nextButton(currentIndex + 1)
                      ],
                    ),
                    positionIndicator(mediaItem, state),
                    Text("Processing state: " +
                        "$processingState".replaceAll(RegExp(r'^.*\.'), '')),
                    StreamBuilder(
                      stream: AudioService.customEventStream,
                      builder: (context, snapshot) {
                        return Text("custom event: ${snapshot.data}");
                      },
                    ),
                    StreamBuilder<bool>(
                      stream: AudioService.notificationClickEventStream,
                      builder: (context, snapshot) {
                        return Text(
                          'Notification Click Status: ${snapshot.data}',
                        );
                      },
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemBuilder: (context, index) {
                          Color color;
                          if (currentIndex != null && currentIndex == index) {
                            color = Colors.red;
                          }
                          return GestureDetector(
                            onTap: () {
                              if (currentIndex != index) {
                                playIndex(index);
                              }
                            },
                            child: ListTile(
                              tileColor: color,
                              title: Text(tracks[index]['title']),
                            ),
                          );
                        },
                        itemCount: tracks.length,
                      ),
                    )
                  ],
                );
              },
            ),
          ),
          SizedBox(height: 50),
        ],
      ),
    );
  }

  /// Encapsulate all the different data we're interested in into a single
  /// stream so we don't have to nest StreamBuilders.
  Stream<PlayerState> get _playerStream =>
      Rx.combineLatest2<PlaybackState, MediaItem, PlayerState>(
          AudioService.playbackStateStream,
          AudioService.currentMediaItemStream,
          (playbackStateStream, mediaItem) =>
              PlayerState(playbackStateStream, mediaItem));

  IconButton playButton() => IconButton(
        icon: Icon(Icons.play_arrow),
        iconSize: 64.0,
        onPressed: play,
      );

  IconButton rewindButton() => IconButton(
        icon: Icon(Icons.refresh),
        onPressed: replay,
        iconSize: 64.0,
      );

  IconButton previousButton(int prevIndex) => IconButton(
        icon: Icon(Icons.skip_previous),
        onPressed: () => AudioService.skipToPrevious(),
        iconSize: 64.0,
      );

  IconButton nextButton(int nextIndex) => IconButton(
        icon: Icon(Icons.skip_next),
        onPressed: () => AudioService.skipToNext(),
        iconSize: 64.0,
      );

  playIndex(int index) {
    AudioService.skipToQueueItem(index.toString());
  }

  replay() {
    AudioService.seekTo(Duration(milliseconds: 0));
  }

  play() {
    if (AudioService.running) {
      AudioService.play();
    } else {
      print('else ma xu ma');
      AudioService.start(
        backgroundTaskEntrypoint: _audioPlayerTaskEntrypoint,
        params: {
          'uri':
              'https://file-examples-com.github.io/uploads/2017/11/file_example_MP3_5MG.mp3',
          'tracks': tracks,
        },
        androidNotificationChannelName: 'Audio Service Demo',
        androidNotificationColor: 0xFF2196f3,
        androidNotificationIcon: 'mipmap/ic_launcher',
        androidEnableQueue: true,
      );
    }
  }

  int _getCurrentTrackIndex(List _tracks, Duration position) {
    return _tracks.lastIndexWhere(
      (element) => position.inMilliseconds > element['start'],
    );
  }

  IconButton pauseButton() => IconButton(
        icon: Icon(Icons.pause),
        iconSize: 64.0,
        onPressed: AudioService.pause,
      );

  IconButton stopButton() => IconButton(
        icon: Icon(Icons.stop),
        iconSize: 64.0,
        onPressed: AudioService.stop,
      );

  Widget positionIndicator(MediaItem mediaItem, PlaybackState state) {
    double seekPos;
    return StreamBuilder(
      // used to cache the user user track position
      // since there is delay in platform channel communication
      stream: Rx.combineLatest2<double, double, double>(
          _dragPositionSubject.stream,
          Stream.periodic(Duration(milliseconds: 200)),
          (dragPosition, _) => dragPosition),
      builder: (context, snapshot) {
        if (state == null) return Text('');
        double position =
            snapshot.data ?? state.currentPosition.inMilliseconds.toDouble();
        double duration = mediaItem?.duration?.inMilliseconds?.toDouble();
        return Column(
          children: [
            if (duration != null)
              Slider(
                min: 0.0,
                max: duration,
                value: seekPos ?? max(0.0, min(position, duration)),
                onChanged: (value) {
                  _dragPositionSubject.add(value);
                },
                onChangeEnd: (value) {
                  AudioService.seekTo(Duration(milliseconds: value.toInt()));
                  // Due to a delay in platform channel communication, there is
                  // a brief moment after releasing the Slider thumb before the
                  // new position is broadcast from the platform side. This
                  // hack is to hold onto seekPos until the next state update
                  // comes through.
                  // TODO: Improve this code.
                  seekPos = value;
                  _dragPositionSubject.add(null);
                },
              ),
            Text("${state.currentPosition}"),
          ],
        );
      },
    );
  }
}

class PlayerState {
  final MediaItem mediaItem;
  final PlaybackState playbackState;

  PlayerState(
    this.playbackState,
    this.mediaItem,
  );
}

// NOTE: Your entrypoint MUST be a top-level function.
void _audioPlayerTaskEntrypoint() async {
  print('ok looks good');
  AudioServiceBackground.run(() => BackgroundAudioService());
}
