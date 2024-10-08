import 'dart:developer';
import 'dart:io';
import 'package:Bloomee/model/saavnModel.dart';
import 'package:Bloomee/model/yt_music_model.dart';
import 'package:Bloomee/repository/Saavn/saavn_api.dart';
import 'package:Bloomee/repository/Youtube/yt_music_api.dart';
import 'package:Bloomee/routes_and_consts/global_conts.dart';
import 'package:Bloomee/routes_and_consts/global_str_consts.dart';
import 'package:Bloomee/screens/widgets/snackbar.dart';
import 'package:Bloomee/services/db/bloomee_db_service.dart';
import 'package:async/async.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:Bloomee/model/songModel.dart';
import 'package:Bloomee/repository/Youtube/youtube_api.dart';
import '../model/MediaPlaylistModel.dart';

List<int> generateRandomIndices(int length) {
  List<int> indices = List<int>.generate(length, (i) => i);
  indices.shuffle();
  return indices;
}

class BloomeeMusicPlayer extends BaseAudioHandler
    with SeekHandler, QueueHandler {
  late AudioPlayer audioPlayer;
  BehaviorSubject<bool> fromPlaylist = BehaviorSubject<bool>.seeded(false);
  BehaviorSubject<bool> isOffline = BehaviorSubject<bool>.seeded(false);
  BehaviorSubject<bool> isLinkProcessing = BehaviorSubject<bool>.seeded(false);
  BehaviorSubject<bool> shuffleMode = BehaviorSubject<bool>.seeded(false);

  BehaviorSubject<List<MediaItem>> relatedSongs =
      BehaviorSubject<List<MediaItem>>.seeded([]);
  BehaviorSubject<LoopMode> loopMode =
      BehaviorSubject<LoopMode>.seeded(LoopMode.off);
  int currentPlayingIdx = 0;
  int shuffleIdx = 0;
  List<int> shuffleList = [];

  bool isPaused = false;

  CancelableOperation<AudioSource?> getLinkOperation =
      CancelableOperation.fromFuture(Future.value());

  BloomeeMusicPlayer() {
    audioPlayer = AudioPlayer(
      handleInterruptions: true,
    );
    audioPlayer.setVolume(1);
    audioPlayer.playbackEventStream.listen(_broadcastPlayerEvent);
    audioPlayer.setLoopMode(LoopMode.off);
  }

  void _broadcastPlayerEvent(PlaybackEvent event) {
    bool isPlaying = audioPlayer.playing;
    // log(event.playing.toString(), name: "bloomeePlayer-event");
    playbackState.add(PlaybackState(
      // Which buttons should appear in the notification now
      controls: [
        MediaControl.skipToPrevious,
        isPlaying ? MediaControl.pause : MediaControl.play,
        // MediaControl.stop,
        MediaControl.skipToNext,
      ],
      processingState: switch (event.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      // Which other actions should be enabled in the notification
      systemActions: const {
        MediaAction.skipToPrevious,
        MediaAction.playPause,
        MediaAction.skipToNext,
        MediaAction.seek,
      },
      androidCompactActionIndices: const [0, 1, 2],
      updatePosition: audioPlayer.position,
      playing: isPlaying,
      bufferedPosition: audioPlayer.bufferedPosition,
      speed: audioPlayer.speed,
      // playing: audioPlayer.playerState.playing,
    ));
  }

  MediaItemModel get currentMedia => queue.value.isNotEmpty
      ? mediaItem2MediaItemModel(queue.value[currentPlayingIdx])
      : mediaItemModelNull;

  @override
  Future<void> play() async {
    if (isLinkProcessing.value == false) {
      await audioPlayer.play();
      log("Playing:", name: "bloomeePlayer");
      isPaused = false;
    } else {
      log("Link is in process...", name: "bloomeePlayer");
      SnackbarService.showMessage("Link is in process...");
    }
  }

  Future<void> check4RelatedSongs() async {
    log("Checking for related songs: ${queue.value.isNotEmpty && (queue.value.length - currentPlayingIdx) < 2}",
        name: "bloomeePlayer");
    if (queue.value.isNotEmpty &&
        (queue.value.length - currentPlayingIdx) < 2 &&
        loopMode.value != LoopMode.all) {
      if (currentMedia.extras?["source"] == "saavn") {
        // final songs = await SaavnAPI().getRelated(currentMedia.id);
        final songs = await compute(SaavnAPI().getRelated, currentMedia.id);
        if (songs['total'] > 0) {
          final List<MediaItem> temp =
              fromSaavnSongMapList2MediaItemList(songs['songs']);
          relatedSongs.add(temp.sublist(1));
          log("Related Songs: ${songs['total']}");
        }
      } else if (currentMedia.extras?["source"].contains("youtube") ?? false) {
        // final songs = await YtMusicService()
        //     .getRelated(currentMedia.id.replaceAll('youtube', ''));
        final songs = await compute(YtMusicService().getRelated,
            currentMedia.id.replaceAll('youtube', ''));
        if (songs['total'] > 0) {
          final List<MediaItem> temp =
              fromYtSongMapList2MediaItemList(songs['songs']);
          relatedSongs.add(temp.sublist(1));
          log("Related Songs: ${songs['total']}");
        }
      }
    }
  }

  Future<void> loadRelatedSongs() async {
    if (relatedSongs.value.isNotEmpty &&
        (queue.value.length - currentPlayingIdx) < 3 &&
        loopMode.value != LoopMode.all) {
      await addQueueItems(relatedSongs.value, atLast: true);
      fromPlaylist.add(false);
      relatedSongs.add([]);
    }
  }

  @override
  Future<void> seek(Duration position) async {
    audioPlayer.seek(position);
  }

  Future<void> seekNSecForward(Duration n) async {
    if ((audioPlayer.duration ?? const Duration(seconds: 0)) >=
        audioPlayer.position + n) {
      await audioPlayer.seek(audioPlayer.position + n);
    } else {
      await audioPlayer
          .seek(audioPlayer.duration ?? const Duration(seconds: 0));
    }
  }

  Future<void> seekNSecBackward(Duration n) async {
    if (audioPlayer.position - n >= const Duration(seconds: 0)) {
      await audioPlayer.seek(audioPlayer.position - n);
    } else {
      await audioPlayer.seek(const Duration(seconds: 0));
    }
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    super.mediaItem.add(mediaItem);
  }

  void setLoopMode(LoopMode loopMode) {
    if (loopMode == LoopMode.one) {
      audioPlayer.setLoopMode(LoopMode.one);
    } else {
      audioPlayer.setLoopMode(LoopMode.off);
    }
    this.loopMode.add(loopMode);
  }

  Future<void> shuffle(bool shuffle) async {
    shuffleMode.add(shuffle);
    if (shuffle) {
      shuffleIdx = 0;
      shuffleList = generateRandomIndices(queue.value.length);
    }
  }

  Future<void> loadPlaylist(MediaPlaylist mediaList,
      {int idx = 0, bool doPlay = false, bool shuffling = false}) async {
    fromPlaylist.add(true);
    queue.add([]);
    relatedSongs.add([]);
    queue.add(mediaList.mediaItems);
    queueTitle.add(mediaList.playlistName);
    shuffle(shuffling);
    if (shuffling) {
      await prepare4play(idx: shuffleList[shuffleIdx], doPlay: doPlay);
    } else {
      await prepare4play(idx: idx, doPlay: doPlay);
    }
    // if (doPlay) play();
  }

  @override
  Future<void> pause() async {
    await audioPlayer.pause();
    isPaused = true;
    log("paused", name: "bloomeePlayer");
  }

  Future<String?> latestYtLink(String id) async {
    final vidInfo = await BloomeeDBService.getYtLinkCache(id);
    if (vidInfo != null) {
      if ((DateTime.now().millisecondsSinceEpoch ~/ 1000) + 350 >
          vidInfo.expireAt) {
        log("Link expired for vidId: $id", name: "bloomeePlayer");
        return await refreshYtLink(id);
      } else {
        log("Link found in cache for vidId: $id", name: "bloomeePlayer");
        String kurl = vidInfo.lowQURL!;
        // await BloomeeDBService.getSettingStr(GlobalStrConsts.ytStrmQuality)
        //     .then((value) {
        //   log("Play quality: $value", name: "bloomeePlayer");
        //   if (value != null) {
        //     if (value == "High") {
        //       kurl = vidInfo.highQURL;
        //     } else {
        //       kurl = vidInfo.lowQURL!;
        //     }
        //   }
        // });
        return kurl;
      }
    } else {
      log("No cache found for vidId: $id", name: "bloomeePlayer");
      return await refreshYtLink(id);
    }
  }

  Future<String?> refreshYtLink(String id) async {
    // String quality = "Low";
    await BloomeeDBService.getSettingStr(GlobalStrConsts.ytStrmQuality)
        .then((value) {
      log('Play quality: $value', name: "bloomeePlayer");
      // if (value != null) {
      //   if (value == "High") {
      //     quality = "High";
      //   } else {
      //     quality = "Low";
      //   }
      // }
    });
    final vidMap = await YouTubeServices().refreshLink(id, quality: "Low");
    if (vidMap != null) {
      return vidMap["url"] as String;
    } else {
      return null;
    }
  }

  Future<AudioSource> getAudioSource(MediaItem mediaItem) async {
    final _down = await BloomeeDBService.getDownloadDB(
        mediaItem2MediaItemModel(mediaItem));
    if (_down != null) {
      log("Playing Offline", name: "bloomeePlayer");
      SnackbarService.showMessage("Playing Offline",
          duration: const Duration(seconds: 1));
      isOffline.add(true);
      return AudioSource.uri(Uri.file('${_down.filePath}/${_down.fileName}'));
    } else {
      isOffline.add(false);
      log("Playing online", name: "bloomeePlayer");
      if (mediaItem.extras?["source"] == "youtube") {
        final id = mediaItem.id.replaceAll("youtube", '');
        final tempStrmLink = await latestYtLink(id);
        if (tempStrmLink != null) {
          return AudioSource.uri(Uri.parse(tempStrmLink));
        }
      }
      String? kurl = await getJsQualityURL(mediaItem.extras?["url"]);
      log('Playing: $kurl', name: "bloomeePlayer");
      return AudioSource.uri(Uri.parse(kurl!));
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < queue.value.length) {
      currentPlayingIdx = index;
      await playMediaItem(queue.value[index]);
    } else {
      await loadRelatedSongs();
      if (index < queue.value.length) {
        currentPlayingIdx = index;
        await playMediaItem(queue.value[index]);
      }
    }

    log("skipToQueueItem", name: "bloomeePlayer");
    return super.skipToQueueItem(index);
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem, {bool doPlay = true}) async {
    updateMediaItem(mediaItem);

    isLinkProcessing.add(true);
    audioPlayer.pause();
    audioPlayer.seek(Duration.zero);

    if (!getLinkOperation.isCompleted) {
      await getLinkOperation.cancel();
    }
    getLinkOperation = CancelableOperation.fromFuture(
      getAudioSource(mediaItem),
      onCancel: () {
        log("skipping....", name: "bloomeePlayer");
        return;
      },
    );

    getLinkOperation.then((value) async {
      if (value != null) {
        try {
          await audioPlayer.setAudioSource(value).then((value) async {
            isLinkProcessing.add(false);
            check4RelatedSongs();
            if (doPlay) {
              log("doPlay", name: "bloomeePlayer");
              await play();
              if (Platform.isWindows && audioPlayer.playing == false) {
                // temp fix for windows (first play not working)
                await play();
              }
            }
          });
        } catch (e) {
          isLinkProcessing.add(false);
          log("Error: $e", name: "bloomeePlayer");
          SnackbarService.showMessage("Error in playing this song: $e");
        }
      }
    });
  }

  Future<void> prepare4play({int idx = 0, bool doPlay = false}) async {
    if (queue.value.isNotEmpty) {
      currentPlayingIdx = idx;
      await playMediaItem(currentMedia, doPlay: doPlay);
      BloomeeDBService.putRecentlyPlayed(MediaItem2MediaItemDB(currentMedia));
    }
  }

  Future<void> playOffsetIdx({int offset = 1}) async {
    if (offset >= 0) {
      if (shuffleMode.value) {
        if (offset + shuffleIdx < queue.value.length) {
          prepare4play(idx: shuffleList[offset + shuffleIdx], doPlay: true);
          shuffleIdx = shuffleIdx + offset;
        }
      } else {
        if (currentPlayingIdx + offset < queue.value.length) {
          prepare4play(idx: offset + currentPlayingIdx, doPlay: true);
        }
      }
    }
  }

  @override
  Future<void> rewind() async {
    if (audioPlayer.processingState == ProcessingState.ready) {
      await audioPlayer.seek(Duration.zero);
    } else if (audioPlayer.processingState == ProcessingState.completed) {
      await prepare4play(idx: currentPlayingIdx);
    }
  }

  @override
  Future<void> skipToNext() async {
    await loadRelatedSongs();
    if (!shuffleMode.value) {
      if (currentPlayingIdx < (queue.value.length - 1)) {
        currentPlayingIdx++;
        prepare4play(idx: currentPlayingIdx, doPlay: true);
      } else if (loopMode.value == LoopMode.all) {
        currentPlayingIdx = 0;
        prepare4play(idx: currentPlayingIdx, doPlay: true);
      }
    } else {
      if (shuffleIdx < (queue.value.length - 1)) {
        shuffleIdx++;
        if (shuffleIdx >= shuffleList.length) {
          shuffleIdx = 0;
        }
        prepare4play(idx: shuffleList[shuffleIdx], doPlay: true);
      } else if (loopMode.value == LoopMode.all) {
        shuffleIdx = 0;
        prepare4play(idx: shuffleList[shuffleIdx], doPlay: true);
      }
    }
  }

  @override
  Future<void> stop() async {
    // log("Called Stop!!");
    audioPlayer.stop();
    super.stop();
  }

  @override
  Future<void> skipToPrevious() async {
    if (!shuffleMode.value) {
      if (currentPlayingIdx > 0) {
        currentPlayingIdx--;
        prepare4play(idx: currentPlayingIdx, doPlay: true);
      }
    } else {
      if (shuffleIdx > 0) {
        shuffleIdx--;
        prepare4play(idx: shuffleList[shuffleIdx], doPlay: true);
      }
    }
  }

  @override
  Future<void> onTaskRemoved() {
    super.stop();
    audioPlayer.dispose();
    return super.onTaskRemoved();
  }

  @override
  Future<void> onNotificationDeleted() {
    audioPlayer.dispose();
    audioPlayer.stop();
    super.stop();

    return super.onNotificationDeleted();
  }

  @override
  Future<void> insertQueueItem(int index, MediaItem mediaItem) async {
    if (index < queue.value.length) {
      queue.value.insert(index, mediaItem);
    } else {
      queue.add(queue.value..add(mediaItem));
    }
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem,
      {bool doPlay = true, bool atLast = false, bool single = false}) async {
    if (single) {
      queue.add([mediaItem]);
      queueTitle.add("Queue");
      relatedSongs.add([]);
      await prepare4play(idx: 0, doPlay: doPlay);
      return;
    }

    if (fromPlaylist.value) {
      fromPlaylist.add(false);
      if (!doPlay) {
        queue.add([currentMedia, mediaItem]);
        currentPlayingIdx = 0;
        if (audioPlayer.processingState == ProcessingState.completed) {
          queue.add([mediaItem]);
          await prepare4play(idx: 0, doPlay: doPlay);
        }
      } else {
        queue.add([mediaItem]);
        await prepare4play(idx: 0, doPlay: doPlay);
      }
    } else {
      if (atLast) {
        queue.add(queue.value..add(mediaItem));
      } else if (currentPlayingIdx >= queue.value.length - 1 ||
          queue.value.isEmpty) {
        queue.add(queue.value..add(mediaItem));
        if (doPlay) {
          await prepare4play(idx: queue.value.length - 1, doPlay: doPlay);
        } else if (audioPlayer.processingState == ProcessingState.completed ||
            queue.value.length == 1) {
          await prepare4play(idx: queue.value.length - 1, doPlay: doPlay);
        }
      } else {
        queue.add(queue.value..insert(currentPlayingIdx + 1, mediaItem));
        if (doPlay) {
          await prepare4play(idx: currentPlayingIdx + 1, doPlay: true);
        }
      }
      shuffle(shuffleMode.value);
    }
    queueTitle.add("Queue");
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems,
      {String queueName = "Queue", bool atLast = false}) async {
    if (!atLast) {
      for (var mediaItem in mediaItems) {
        await addQueueItem(
          mediaItem,
          atLast: true,
        );
      }
    } else {
      if (fromPlaylist.value) {
        fromPlaylist.add(false);
      }
      queue.add(queue.value..addAll(mediaItems));
      queueTitle.add("Queue");
    }
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    queue.value.removeAt(index);
  }
}
