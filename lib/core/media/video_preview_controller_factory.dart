import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'video_preview_controller_web.dart'
    if (dart.library.io) 'video_preview_controller_io.dart' as platform;

VideoPlayerController createVideoPreviewController(XFile file) =>
    platform.createVideoPreviewController(file);
