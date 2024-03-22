// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:Bloomee/model/songModel.dart';
import 'package:Bloomee/services/db/GlobalDB.dart';

class MediaPlaylist {
  late List<MediaItemModel> mediaItems;
  bool isLiked = false;
  String albumName = "Unknown";
  MediaPlaylist({
    required this.mediaItems,
    this.isLiked = false,
    required this.albumName,
  });
}

MediaPlaylist fromPlaylistDB2MediaPlaylist(MediaPlaylistDB mediaPlaylistDB) {
  MediaPlaylist mediaPlaylist =
      MediaPlaylist(mediaItems: [], albumName: mediaPlaylistDB.playlistName);
  if (mediaPlaylistDB.mediaItems.isNotEmpty) {
    mediaPlaylistDB.mediaItems.forEach((element) {
      mediaPlaylist.mediaItems.add(MediaItemDB2MediaItem(element));
    });
  }
  return mediaPlaylist;
}
