import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

VideoPlayerController createVideoPreviewController(XFile file) {
  final path = file.path.trim();
  if (path.isEmpty) {
    throw ArgumentError.value(path, 'file.path', 'URL de média vide.');
  }
  return VideoPlayerController.networkUrl(Uri.parse(path));
}
