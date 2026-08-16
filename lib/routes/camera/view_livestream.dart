//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:flutter/services.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/notifications/heartbeat_task.dart';
import 'package:secluso_flutter/utilities/byte_stream_player.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:secluso_flutter/utilities/byte_player_view.dart';
import 'package:secluso_flutter/utilities/app_paths.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/result.dart';
import 'package:path/path.dart' as p;
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/ui/google_fonts.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/routes/app_drawer.dart';
import 'package:secluso_flutter/routes/camera/view_camera.dart';
import 'package:secluso_flutter/ui/secluso_surfaces.dart';
import 'package:secluso_flutter/ui/secluso_theme.dart';
import 'package:secluso_flutter/utilities/video_thumbnail_store.dart';
import 'dart:io';

// Covers the camera's pipeline warmup before chunk 1
const _livestreamStaleChunkThreshold = Duration(seconds: 10);

class LivestreamPage extends StatefulWidget {
  final String cameraName;
  final String? previewAssetPath;
  final String? previewVideoAssetPath;
  final bool previewStreaming;
  final String? previewErrorMessage;

  const LivestreamPage({
    super.key,
    required this.cameraName,
    this.previewAssetPath,
    this.previewVideoAssetPath,
    this.previewStreaming = true,
    this.previewErrorMessage,
  });

  @override
  State<LivestreamPage> createState() => _LivestreamPageState();
}

class _LivestreamPageState extends State<LivestreamPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  bool isStreaming = false;
  bool hasFailed = false;
  String _errMsg = '';
  double? _aspectRatio;
  int? _streamId;
  bool _hasRenderedFirstFrame = false;
  bool _streamPaused = false;
  bool _isClosing = false;
  Future<void>? _shutdownFuture;
  Future<void> _archiveWriteChain = Future.value();
  File? _archiveVideoFile;
  Uint8List? _archiveThumbnailBytes;
  bool _archiveInitialized = false;
  bool _archiveHasWrittenBytes = false;
  VideoPlayerController? _previewController;
  late final AnimationController _connectingPulseController =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      )..repeat(reverse: true);
  late final AnimationController _loadingOrbitController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();
  late final AnimationController _loadingAccentController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  MethodChannel? _methodChannel;
  AppLifecycleState?
  _lastLifecycleState; // Store the lifecycle state that was last to ensure we don't cancel the livestream for screen rotation
  Future<void>? _chunkPumpFuture;

  bool get _isPreviewMode =>
      widget.previewAssetPath != null ||
      widget.previewVideoAssetPath != null ||
      widget.previewErrorMessage != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_isPreviewMode) {
      isStreaming = widget.previewStreaming;
      hasFailed = widget.previewErrorMessage != null;
      _errMsg = widget.previewErrorMessage ?? '';
      _aspectRatio = 16 / 9;
      if (widget.previewVideoAssetPath != null) {
        unawaited(_initPreviewVideo());
      }
      return;
    }
    _startLivestream();
  }

  void _markFirstFrameReady(String source) {
    if (_hasRenderedFirstFrame) {
      return;
    }
    Log.d('Livestream first-frame gate cleared via $source');
    if (mounted) {
      setState(() {
        _hasRenderedFirstFrame = true;
      });
    } else {
      _hasRenderedFirstFrame = true;
    }
  }

  void _pauseLivestream(String reason) {
    Log.w('Livestream paused - $reason');
    if (mounted) {
      setState(() {
        _streamPaused = true;
        isStreaming = false;
      });
    } else {
      _streamPaused = true;
      isStreaming = false;
    }
  }

  void _clearMethodChannel() {
    final channel = _methodChannel;
    _methodChannel = null;
    if (channel == null) {
      return;
    }
    try {
      channel.setMethodCallHandler(null);
    } catch (_) {}
  }

  @override
  void dispose() {
    // Clear method channel after gone
    if (!_isPreviewMode) {
      _clearMethodChannel();

      if (_streamId != null && _shutdownFuture == null) {
        unawaited(_finishNativeStream());
      }
    }
    _connectingPulseController.dispose();
    _loadingOrbitController.dispose();
    _loadingAccentController.dispose();
    _previewController?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initPreviewVideo() async {
    try {
      final controller = VideoPlayerController.asset(
        widget.previewVideoAssetPath!,
      );
      _previewController = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _aspectRatio =
            controller.value.aspectRatio > 0
                ? controller.value.aspectRatio
                : 16 / 9;
      });
    } catch (e, st) {
      Log.e('Failed to initialize review livestream preview: $e\n$st');
      if (!mounted) return;
      setState(() {
        hasFailed = true;
        _errMsg = 'Unable to load the App Review live preview.';
      });
    }
  }

  // Push channel for chunk arrivals. Null falls back to timer polling.
  WebSocket? _eventSocket;
  StreamController<void>? _chunkSignal;

  Future<void> _connectEventSocket() async {
    _chunkSignal ??= StreamController<void>.broadcast();
    final socket = await HttpClientService.instance.livestreamEventSocket(
      widget.cameraName,
    );
    if (socket == null || !mounted || !isStreaming) {
      await socket?.close();
      return;
    }
    _eventSocket = socket;
    socket.listen(
      (data) {
        try {
          final event = jsonDecode(data as String);
          if (event is Map && event['type'] == 'chunk') {
            _chunkSignal?.add(null);
          }
        } catch (_) {}
      },
      onError: (_) => _eventSocket = null,
      onDone: () => _eventSocket = null,
      cancelOnError: true,
    );
  }

  Future<void> _waitForChunk(Duration timeout) async {
    final signal = _chunkSignal;
    if (signal == null || _eventSocket == null) {
      await Future.delayed(timeout);
      return;
    }
    try {
      await signal.stream.first.timeout(timeout);
    } on TimeoutException {}
  }

  Future<void> _closeEventSocket() async {
    final socket = _eventSocket;
    _eventSocket = null;
    await socket?.close();
    await _chunkSignal?.close();
    _chunkSignal = null;
  }

  Future<void> _startLivestream() async {
    Log.d('Entered method');

    final prefs = await SharedPreferences.getInstance();

    var recordingMotion =
        prefs.getBool(
          PrefKeys.recordingMotionVideosPrefix + widget.cameraName,
        ) ??
        false;
    var lastRecordingTimestamp =
        prefs.getInt(
          PrefKeys.lastRecordingTimestampPrefix + widget.cameraName,
        ) ??
        0;
    var nowTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (recordingMotion && (nowTimestamp - lastRecordingTimestamp) < 60) {
      _fail(
        'The camera is recording a video to send to the app and cannot livestream now. Please try again in a couple of seconds.',
      );
      return;
    }

    for (int i = 0; i < 2; i++) {
      final startRes = await HttpClientService.instance.livestreamStart(
        widget.cameraName,
      );

      bool startSucceeded = false;
      await startRes.fold(
        (_) async {
          Log.d('Launching native player');
          try {
            _hasRenderedFirstFrame = false;
            _streamId = await ByteStreamPlayer.createStream();
            Log.d('Native queue id = $_streamId');
            _methodChannel = MethodChannel('byte_player_view_$_streamId');
            _methodChannel!.setMethodCallHandler((call) async {
              if (call.method == 'onAspectRatio') {
                final ratio = call.arguments as double;
                Log.d("Recieved aspect ratio $ratio");
                if (ratio > 0 && mounted) {
                  setState(() {
                    _aspectRatio = ratio;
                  });
                }
              } else if (call.method == 'onFirstFrame') {
                _markFirstFrameReady('native');
              } else if (call.method == 'onThumbnailBytes') {
                final bytes = call.arguments as Uint8List?;
                if (bytes != null && bytes.isNotEmpty) {
                  _archiveThumbnailBytes = bytes;
                  Log.d(
                    'Captured livestream thumbnail bytes (${bytes.length} B)',
                  );
                }
              } else if (call.method == "debug") {
                // Plain text log line from swift livestream debug code
                final msg = call.arguments as String? ?? '';
                Log.d('[native] $msg');
              }
            });
          } catch (e) {
            _fail('Could not start native player: $e');
            return;
          }

          final cmOk = await _retrieveAndApplyCommitMsg();
          if (!cmOk) return; // error handled inside

          setState(() => isStreaming = true);
          _streamPaused = false;
          unawaited(_connectEventSocket());
          _chunkPumpFuture = _startChunkPump();
          startSucceeded = true;
          return;
        },
        (err) async {
          if (i == 1) {
            _fail('Failed: $err');
            return;
          }
        },
      );

      if (startSucceeded || i == 1) {
        return;
      }

      // We get here when we get an error trying to start livestream.
      // One possibility for the error is that there is a pending commit message (chunk 0)
      // from a previous failed attempt on the server.
      // In that case, we need to apply that and then try to start livestream again.
      await _tryRetrieveAndApplyCommitMSg();
    }
  }

  Future<bool> _tryRetrieveAndApplyCommitMSg() async {
    final res = await HttpClientService.instance.livestreamRetrieve(
      cameraName: widget.cameraName,
      chunkNumber: 0,
    );

    final ok = await res.fold(
      (bytes) async {
        final updated = await livestreamUpdate(
          cameraName: widget.cameraName,
          msg: bytes,
        );

        if (!updated) {
          _fail('Could not apply commit message');
          return false;
        }

        return true;
      },
      (err) async {
        Log.d('Commit error: $err');
        return false;
      },
    );
    if (ok) {
      Log.d('Commit applied');
      return true;
    }

    return ok;
  }

  Future<bool> _retrieveAndApplyCommitMsg() async {
    Log.d('Fetch commit msg (chunk 0)…');
    int attempt = 0;

    while (true) {
      final res = await _tryRetrieveAndApplyCommitMSg();
      if (res == true) {
        return true;
      }
      // The camera needs a moment to notice the request, commit, and upload chunk 0
      if (++attempt > 15) {
        _fail('Could not retrieve commit message after 15 retries');
        return false;
      }
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Future<_ChunkFetchSnapshot> _fetchChunkSnapshot(int chunkNumber) async {
    final startedAtMs = DateTime.now().millisecondsSinceEpoch;
    final result = await HttpClientService.instance.livestreamRetrieve(
      cameraName: widget.cameraName,
      chunkNumber: chunkNumber,
    );
    final completedAtMs = DateTime.now().millisecondsSinceEpoch;
    return _ChunkFetchSnapshot(
      chunkNumber: chunkNumber,
      startedAtMs: startedAtMs,
      completedAtMs: completedAtMs,
      result: result,
    );
  }

  void _enqueueArchiveWrite(Uint8List dec) {
    final payload = Uint8List.fromList(dec);
    _archiveWriteChain = _archiveWriteChain
        .then((_) => _writeArchiveChunk(payload))
        .catchError((Object e, StackTrace st) {
          Log.e('Livestream archive write error: $e\n$st');
        });
  }

  Future<void> _writeArchiveChunk(Uint8List dec) async {
    if (!_archiveInitialized) {
      final baseDir = await AppPaths.dataDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final videoName = 'video_$timestamp.mp4';
      final filePath = p.join(
        baseDir.path,
        'camera_dir_${widget.cameraName}',
        'videos',
        videoName,
      );

      final parentDir = Directory(p.dirname(filePath));
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      _archiveVideoFile = File(filePath);
      _archiveInitialized = true;

      if (!AppStores.isInitialized) {
        await AppStores.init();
      }

      await AppStores.instance.videoStore.put(
        Video(widget.cameraName, videoName, true, false),
      );

      final foundCamera = await AppStores.instance.cameraStore.findFirstByName(
        widget.cameraName,
      );

      if (foundCamera == null) {
        Log.e(
          "Camera entity is null in database. This shouldn't be possible. Camera: ${widget.cameraName} Video: $videoName",
        );
      } else if (globalCameraViewPageState?.mounted == true &&
          globalCameraViewPageState?.widget.cameraName == widget.cameraName) {
        globalCameraViewPageState?.reloadVideos();
      }
    }

    final file = _archiveVideoFile;
    if (file == null) {
      Log.e('Livestream archive file not initialized');
      return;
    }

    await file.writeAsBytes(
      dec,
      mode:
          _archiveHasWrittenBytes
              ? FileMode.writeOnlyAppend
              : FileMode.writeOnly,
    );
    _archiveHasWrittenBytes = true;
  }

  // bytes to queue action
  Future<void> _startChunkPump() async {
    Log.d('Start chunk pump');
    int chunk = 1;
    final id = _streamId!;
    var lastChunkTime = DateTime.now().millisecondsSinceEpoch;
    Future<_ChunkFetchSnapshot> currentFetch = _fetchChunkSnapshot(chunk);

    while (isStreaming) {
      final snapshot = await currentFetch;
      final chunkPipelineStartMs = DateTime.now().millisecondsSinceEpoch;

      await snapshot.result.fold(
        (enc) async {
          final nextChunk = chunk + 1;
          final prefetchStartMs = DateTime.now().millisecondsSinceEpoch;
          final nextFetch = _fetchChunkSnapshot(nextChunk);

          final statusStartMs = DateTime.now().millisecondsSinceEpoch;
          updateCameraStatusLivestream(widget.cameraName);
          final statusDoneMs = DateTime.now().millisecondsSinceEpoch;

          final decryptStartMs = DateTime.now().millisecondsSinceEpoch;
          final dec = await livestreamDecrypt(
            cameraName: widget.cameraName,
            data: enc,
            expectedChunkNumber: BigInt.from(chunk),
          );
          final decryptDoneMs = DateTime.now().millisecondsSinceEpoch;

          final pushStartMs = DateTime.now().millisecondsSinceEpoch;
          await ByteStreamPlayer.push(id, dec);
          final pushDoneMs = DateTime.now().millisecondsSinceEpoch;

          final archiveEnqueueStartMs = DateTime.now().millisecondsSinceEpoch;
          _enqueueArchiveWrite(dec);
          final archiveEnqueueDoneMs = DateTime.now().millisecondsSinceEpoch;

          final chunkDoneMs = DateTime.now().millisecondsSinceEpoch;
          Log.d(
            'Livestream timings: '
            'chunk $chunk, '
            'fetch=${snapshot.completedAtMs - snapshot.startedAtMs} ms, '
            'status=${statusDoneMs - statusStartMs} ms, '
            'decrypt=${decryptDoneMs - decryptStartMs} ms, '
            'push=${pushDoneMs - pushStartMs} ms, '
            'archiveEnqueue=${archiveEnqueueDoneMs - archiveEnqueueStartMs} ms, '
            'process=${chunkDoneMs - chunkPipelineStartMs} ms, '
            'sinceLast=${chunkDoneMs - lastChunkTime} ms, '
            'nextPrefetchStartedIn=${prefetchStartMs - chunkPipelineStartMs} ms',
          );
          lastChunkTime = chunkDoneMs;

          if (chunk == 1) {
            final first16 = dec
                .take(16)
                .map((b) => b.toRadixString(16).padLeft(2, '0'));
            Log.d('First 16 bytes: $first16');
          }

          Log.d('Pushed chunk $chunk (${dec.length} B)');
          if (defaultTargetPlatform == TargetPlatform.android && chunk == 1) {
            _markFirstFrameReady('android-first-chunk');
          }

          chunk++;
          currentFetch = nextFetch;
        },
        (err) async {
          final errText = err.toString();
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final sinceLastSuccessMs = nowMs - lastChunkTime;
          Log.d(
            'Chunk $chunk error after fetch=${snapshot.completedAtMs - snapshot.startedAtMs} ms '
            '(sinceLastSuccess=$sinceLastSuccessMs ms): $errText',
          );
          // 404 just means the camera hasn't uploaded this chunk yet
          if (!_isClosing &&
              sinceLastSuccessMs >=
                  _livestreamStaleChunkThreshold.inMilliseconds) {
            final pauseReason =
                errText.contains('404 Not Found')
                    ? 'No new video received for chunk $chunk'
                    : 'No successful livestream chunk for $sinceLastSuccessMs ms ($errText)';
            _pauseLivestream(pauseReason);
            return;
          }
          await _waitForChunk(const Duration(milliseconds: 500));
          currentFetch = _fetchChunkSnapshot(chunk);
          // TODO: At some point, we should stop trying to find more chunks... show user an error. Also, what if a user closes out of the page? This continues on.
        },
      );
    }

    Log.d('Pump exited');
  }

  //finish / error
  Future<void> _finishNativeStream() async {
    await _closeEventSocket();
    final id = _streamId;
    if (id != null) {
      _streamId = null;
      _clearMethodChannel();
      await _archiveWriteChain;
      await ByteStreamPlayer.push(id, Uint8List(0)); // EOF
      await ByteStreamPlayer.finish(id);
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await ByteStreamPlayer.disposeView(id);
      }

      await HttpClientService.instance.livestreamEnd(widget.cameraName);

      Log.d('Completed method');
    }
  }

  void _resetArchiveState() {
    _archiveWriteChain = Future.value();
    _archiveVideoFile = null;
    _archiveThumbnailBytes = null;
    _archiveInitialized = false;
    _archiveHasWrittenBytes = false;
  }

  Future<void> _finalizeArchivedVideo() async {
    final archiveFile = _archiveVideoFile;
    if (archiveFile == null) {
      _resetArchiveState();
      return;
    }

    try {
      if (!await archiveFile.exists()) {
        return;
      }

      final videoFile = p.basename(archiveFile.path);
      final bytes =
          await _writeCapturedArchiveThumbnail(videoFile) ??
          await VideoThumbnailStore.loadOrGenerate(
            cameraName: widget.cameraName,
            videoFile: videoFile,
            logPrefix: 'Livestream archive thumb',
          );
      if (bytes == null) {
        Log.w(
          'Livestream archive thumbnail generation failed for ${widget.cameraName}/$videoFile',
        );
        return;
      }

      camerasPageKey.currentState?.invalidateThumbnail(widget.cameraName);
      if (globalCameraViewPageState?.mounted == true &&
          globalCameraViewPageState?.widget.cameraName == widget.cameraName) {
        await globalCameraViewPageState?.reloadVideos();
      }

      Log.d(
        'Livestream archive thumbnail ready for ${widget.cameraName}/$videoFile (${bytes.length} B)',
      );
    } catch (e, st) {
      Log.e('Livestream archive finalization error: $e\n$st');
    } finally {
      _resetArchiveState();
    }
  }

  Future<Uint8List?> _writeCapturedArchiveThumbnail(String videoFile) async {
    final bytes = _archiveThumbnailBytes;
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    final archiveFile = _archiveVideoFile;
    final timestamp = VideoThumbnailStore.timestampTokenFromVideo(videoFile);
    if (archiveFile == null || timestamp == null) {
      return null;
    }

    final thumbPath = p.join(
      p.dirname(archiveFile.path),
      'thumbnail_$timestamp.png',
    );
    try {
      await File(thumbPath).writeAsBytes(bytes, flush: true);
      Log.d(
        'Wrote captured livestream thumbnail for ${widget.cameraName}/$videoFile -> $thumbPath',
      );
      return bytes;
    } catch (e, st) {
      Log.e('Failed writing captured livestream thumbnail: $e\n$st');
      return null;
    }
  }

  Future<void> _closeLivestream() async {
    if (_isPreviewMode) {
      if (mounted) {
        Navigator.of(context).maybePop();
      }
      return;
    }
    if (_isClosing) {
      return _shutdownFuture ?? Future.value();
    }

    _isClosing = true;
    if (mounted) {
      setState(() => isStreaming = false);
    } else {
      isStreaming = false;
    }

    final shutdownFuture = _finishNativeStream();
    _shutdownFuture = shutdownFuture;
    await shutdownFuture;
    await (_chunkPumpFuture ?? Future.value());
    _chunkPumpFuture = null;
    await _archiveWriteChain;
    await _finalizeArchivedVideo();

    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  void _fail(String msg) {
    Log.e('Livestream fail - $msg');
    setState(() {
      hasFailed = true;
      _streamPaused = false;
      _errMsg = msg;
    });
  }

  Future<void> _retryConnection() async {
    if (_isPreviewMode) {
      setState(() {
        hasFailed = false;
        _streamPaused = false;
        _errMsg = '';
        isStreaming = true;
      });
      return;
    }

    final existingStreamId = _streamId;
    if (mounted) {
      setState(() {
        hasFailed = false;
        _streamPaused = false;
        _errMsg = '';
        isStreaming = false;
        _hasRenderedFirstFrame = false;
      });
    } else {
      hasFailed = false;
      _streamPaused = false;
      _errMsg = '';
      isStreaming = false;
      _hasRenderedFirstFrame = false;
    }
    if (existingStreamId != null) {
      await _finishNativeStream();
      await (_chunkPumpFuture ?? Future.value());
      _chunkPumpFuture = null;
      await _archiveWriteChain;
      await _finalizeArchivedVideo();
    }
    _startLivestream();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    Log.i("Changed state to ${state.name}");
    if (_lastLifecycleState != null) {
      Log.i("last state was ${_lastLifecycleState!.name}");
    }

    if (state == AppLifecycleState.resumed) {
      Log.i("App Lifecycle State set to RESUMED within livestream");

      // Only pop if last state was in background (not screen rotation)
      if (_lastLifecycleState == AppLifecycleState.paused ||
          _lastLifecycleState == AppLifecycleState.hidden) {
        if (mounted) {
          setState(() => isStreaming = false);
          Navigator.pop(context);
        }
      }
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (mounted) {
        setState(() => isStreaming = false);
      }
    }

    _lastLifecycleState = state;
  }

  void _showUnimplementedLivestreamControl() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Unimplemented')));
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final showNativeShell = !_isPreviewMode && !hasFailed;
    final loadingLiveFrame =
        !_isPreviewMode &&
        !_streamPaused &&
        (!isStreaming || !_hasRenderedFirstFrame);
    return SeclusoScaffold(
      appBar:
          isLandscape ||
                  hasFailed ||
                  _streamPaused ||
                  isStreaming ||
                  showNativeShell
              ? null
              : seclusoAppBar(
                context,
                title: '',
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    Log.i("Back button pressed");
                    setState(() => isStreaming = false);
                    Navigator.pop(context);
                  },
                ),
              ),
      body:
          hasFailed || _streamPaused
              ? _buildFailureState(paused: _streamPaused)
              : isLandscape
              ? (_isPreviewMode
                  ? _buildPreviewStream()
                  : _buildLandscapeLiveStream(loading: loadingLiveFrame))
              : (_isPreviewMode
                  ? _buildPortraitPreviewStream()
                  : _buildPortraitLiveStream(loading: loadingLiveFrame)),

      floatingActionButton:
          isStreaming && isLandscape
              ? FloatingActionButton.extended(
                backgroundColor: SeclusoColors.danger,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
                onPressed: () {
                  if (_isPreviewMode) {
                    Navigator.pop(context);
                  } else {
                    setState(() => isStreaming = false);
                    Navigator.pop(context);
                  }
                },
              )
              : null,
    );
  }

  Widget _buildPortraitLiveStream({bool loading = false}) {
    return _buildPortraitWorkingState(
      loading: loading,
      media: _buildLiveVideoMedia(loading: loading),
    );
  }

  Widget _buildLandscapeLiveStream({bool loading = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = _aspectRatio ?? 16 / 9;
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        double videoWidth = screenWidth;
        double videoHeight = videoWidth / ratio;

        if (videoHeight > screenHeight) {
          videoHeight = screenHeight;
          videoWidth = videoHeight * ratio;
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: videoWidth,
              height: videoHeight,
              child: _buildLiveVideoMedia(loading: loading),
            ),
            Positioned(
              bottom: 24,
              child: SeclusoStatusChip(
                label:
                    _streamPaused
                        ? 'Paused · end-to-end encrypted'
                        : loading
                        ? 'Connecting · end-to-end encrypted'
                        : 'Live · end-to-end encrypted',
                icon: Icons.lock_outline,
                color:
                    _streamPaused
                        ? const Color(0xFFF59E0B)
                        : loading
                        ? SeclusoColors.blue
                        : SeclusoColors.success,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPortraitPreviewStream() {
    return _buildPortraitWorkingState(media: _buildPreviewMedia());
  }

  Widget _buildPreviewMedia() {
    final previewController = _previewController;
    if (previewController != null && previewController.value.isInitialized) {
      return _LivestreamCoverMedia(
        aspectRatio: previewController.value.aspectRatio,
        child: VideoPlayer(previewController),
      );
    }
    if (widget.previewAssetPath != null) {
      return Image.asset(widget.previewAssetPath!, fit: BoxFit.cover);
    }
    return const ColoredBox(color: Colors.black);
  }

  Widget _buildLiveVideoMedia({required bool loading}) {
    final media =
        _streamId == null
            ? const SizedBox.shrink()
            : BytePlayerView(streamId: _streamId!);
    return _LivestreamCoverMedia(
      aspectRatio: _aspectRatio ?? (16 / 9),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: media),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: loading ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _loadingOrbitController,
                    _loadingAccentController,
                  ]),
                  builder:
                      (context, _) => _LivestreamLoadingMedia(
                        orbitValue: _loadingOrbitController.value,
                        accentValue: _loadingAccentController.value,
                      ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitWorkingState({
    required Widget media,
    bool loading = false,
  }) {
    final theme = Theme.of(context);
    final showDevOnlyControls = kDebugMode;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullScreenHeight = MediaQuery.sizeOf(context).height;
        final metrics = _LivestreamWorkingMetrics.forViewport(
          constraints.maxWidth,
          fullScreenHeight,
        );
        return ColoredBox(
          color: Colors.black,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: metrics.bottomPadding),
            child: Center(
              child: SizedBox(
                width: metrics.canvasWidth,
                height: metrics.canvasHeight,
                child: Stack(
                  children: [
                    Positioned(
                      left: metrics.backButtonLeft,
                      top: metrics.backButtonTop,
                      child: _LivestreamWorkingBackButton(
                        size: metrics.backButtonSize,
                        iconSize: metrics.backButtonIconSize,
                        onTap: () {
                          if (_isPreviewMode) {
                            Navigator.of(context).maybePop();
                          } else {
                            unawaited(_closeLivestream());
                          }
                        },
                      ),
                    ),
                    Positioned(
                      left: metrics.headerTitleLeft,
                      top: metrics.headerTitleTop,
                      width: metrics.headerTitleWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.cameraName,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              textStyle: theme.textTheme.titleMedium,
                              color: Colors.white,
                              fontSize: metrics.headerTitleSize,
                              fontWeight: FontWeight.w600,
                              height: 19.5 / 13,
                            ),
                          ),
                          SizedBox(height: 4 * metrics.scale),
                          AnimatedBuilder(
                            animation: _connectingPulseController,
                            builder: (context, _) {
                              final opacity =
                                  loading
                                      ? 0.45 +
                                          (_connectingPulseController.value *
                                              0.55)
                                      : 0.85;
                              final dotColor =
                                  _streamPaused
                                      ? const Color(0xFFF59E0B)
                                      : loading
                                      ? const Color(0xFF8BB3EE)
                                      : const Color(0xFFEF4444);
                              final liveLabel =
                                  _streamPaused
                                      ? 'PAUSED'
                                      : loading
                                      ? 'CONNECTING'
                                      : 'LIVE';
                              return Opacity(
                                opacity: opacity,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: metrics.liveDotSize,
                                      height: metrics.liveDotSize,
                                      decoration: BoxDecoration(
                                        color: dotColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    SizedBox(width: 4 * metrics.scale),
                                    Text(
                                      liveLabel,
                                      style: GoogleFonts.inter(
                                        textStyle: theme.textTheme.labelSmall,
                                        color: Colors.white,
                                        fontSize: metrics.liveLabelSize,
                                        fontWeight: FontWeight.w400,
                                        letterSpacing:
                                            loading
                                                ? metrics
                                                        .liveLabelLetterSpacing *
                                                    0.8
                                                : metrics
                                                    .liveLabelLetterSpacing,
                                        height: 13.5 / 9,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: metrics.e2eeRight,
                      top: metrics.e2eeTop,
                      child: _LivestreamWorkingChip(metrics: metrics),
                    ),
                    Positioned(
                      left: metrics.videoLeft,
                      top: metrics.videoTop,
                      width: metrics.videoWidth,
                      height: metrics.videoHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0A0A),
                          borderRadius: BorderRadius.circular(
                            metrics.videoRadius,
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            metrics.videoRadius - (metrics.scale * 0.5),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Positioned.fill(child: media),
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      center: Alignment.center,
                                      radius: 1.15,
                                      stops: const [0.5, 1],
                                      colors: [
                                        Colors.black.withValues(alpha: 0),
                                        Colors.black.withValues(alpha: 0.6),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: metrics.controlPanelLeft,
                      top: metrics.controlPanelTop,
                      width: metrics.controlPanelWidth,
                      height: metrics.controlPanelHeight,
                      child: _LivestreamWorkingControlPanel(
                        metrics: metrics,
                        showDevOnlyControls: showDevOnlyControls,
                        onBackThirty: _showUnimplementedLivestreamControl,
                        onMute: _showUnimplementedLivestreamControl,
                        onStop: () {
                          if (_isPreviewMode) {
                            Navigator.of(context).maybePop();
                          } else {
                            unawaited(_closeLivestream());
                          }
                        },
                        onPhoto: _showUnimplementedLivestreamControl,
                      ),
                    ),
                    if (showDevOnlyControls)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: metrics.micLabelTop,
                        child: Text(
                          'Microphone Muted',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            textStyle: theme.textTheme.bodySmall,
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: metrics.micLabelSize,
                            fontWeight: FontWeight.w400,
                            height: 13.5 / 9,
                          ),
                        ),
                      ),
                    Positioned(
                      left: (metrics.canvasWidth - metrics.footerWidth) / 2,
                      top: metrics.footerTop,
                      width: metrics.footerWidth,
                      child: Text(
                        'END-TO-END ENCRYPTED · PEER-TO-PEER',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          textStyle: theme.textTheme.labelSmall,
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: metrics.footerSize,
                          fontWeight: FontWeight.w400,
                          letterSpacing: metrics.footerLetterSpacing,
                          height: 13.5 / 9,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFailureState({bool paused = false}) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final backgroundColor =
        dark ? const Color(0xFF050505) : const Color(0xFFF2F2F7);
    final headerColor = dark ? Colors.white : const Color(0xFF111827);
    final bodyColor =
        dark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF6B7280);
    final surfaceColor =
        dark ? Colors.white.withValues(alpha: 0.03) : Colors.white;
    final surfaceBorderColor =
        dark ? Colors.white.withValues(alpha: 0.05) : const Color(0x0A000000);
    final surfaceShadow =
        dark
            ? const <BoxShadow>[]
            : const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ];
    final mutedHeadingColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF9CA3AF);
    final badgeColor =
        dark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF3F4F6);
    final badgeTextColor =
        dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF9CA3AF);
    final checklistTextColor =
        dark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF4B5563);
    final backButtonFill =
        dark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE5E7EB);
    final backButtonIconColor = dark ? Colors.white : const Color(0xFF6B7280);
    final errorCardFill = const Color(0x14EF4444);
    final errorCardBorder =
        dark ? const Color(0x26EF4444) : const Color(0x4DEF4444);
    final headerSubtitle = paused ? 'Stream paused' : 'Stream unavailable';
    final failureTitle = paused ? 'Live feed paused' : 'Unable to connect';
    final failureBody =
        paused
            ? 'No new video received from this camera.'
            : _errMsg.isEmpty
            ? "The peer-to-peer connection to ${widget.cameraName} couldn't be established."
            : _errMsg;
    final actionLabel = paused ? 'RETRY STREAM' : 'TRY AGAIN';
    final closeLabel = paused ? 'Close' : 'Back to ${widget.cameraName}';
    return ColoredBox(
      color: backgroundColor,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fullScreenHeight = MediaQuery.sizeOf(context).height;
            final metrics = _LivestreamFailureMetrics.forViewport(
              constraints.maxWidth,
              fullScreenHeight,
            );
            final backLabelTop =
                paused ? metrics.retryRowTop : metrics.backLabelTop;
            return SingleChildScrollView(
              padding: EdgeInsets.only(bottom: metrics.bottomInset),
              child: Center(
                child: SizedBox(
                  width: metrics.canvasWidth,
                  height: metrics.canvasHeight,
                  child: Stack(
                    children: [
                      Positioned(
                        left: metrics.backButtonLeft,
                        top: metrics.headerTop,
                        child: _FailureBackButton(
                          size: metrics.backButtonSize,
                          iconSize: metrics.backIconSize,
                          fillColor: backButtonFill,
                          iconColor: backButtonIconColor,
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                      Positioned(
                        left: metrics.headerTextLeft,
                        top: metrics.headerTitleTop,
                        child: Text(
                          widget.cameraName,
                          style: GoogleFonts.inter(
                            textStyle: theme.textTheme.titleLarge,
                            color: headerColor,
                            fontSize: metrics.headerTitleSize,
                            fontWeight: FontWeight.w600,
                            height: 28 / 18,
                          ),
                        ),
                      ),
                      Positioned(
                        left: metrics.headerTextLeft,
                        top: metrics.headerSubtitleTop,
                        child: Text(
                          headerSubtitle,
                          style: GoogleFonts.inter(
                            textStyle: theme.textTheme.bodySmall,
                            color: const Color(0xFFEF4444),
                            fontSize: metrics.headerSubtitleSize,
                            fontWeight: FontWeight.w400,
                            height: 15 / 10,
                          ),
                        ),
                      ),
                      Positioned(
                        left:
                            (metrics.canvasWidth - metrics.errorIconCardSize) /
                            2,
                        top: metrics.errorIconTop,
                        child: Container(
                          width: metrics.errorIconCardSize,
                          height: metrics.errorIconCardSize,
                          decoration: BoxDecoration(
                            color: errorCardFill,
                            borderRadius: BorderRadius.circular(
                              metrics.errorIconCardRadius,
                            ),
                            border: Border.all(color: errorCardBorder),
                          ),
                          child: Icon(
                            paused
                                ? Icons.pause_circle_outline_rounded
                                : Icons.videocam_off_outlined,
                            color: const Color(0xFFEF4444),
                            size: metrics.errorIconSize,
                          ),
                        ),
                      ),
                      Positioned(
                        left:
                            (metrics.canvasWidth - metrics.failureTitleWidth) /
                            2,
                        top: metrics.failureTitleTop,
                        width: metrics.failureTitleWidth,
                        child: Text(
                          failureTitle,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            textStyle: theme.textTheme.titleLarge,
                            color: headerColor,
                            fontSize: metrics.failureTitleSize,
                            fontWeight: FontWeight.w600,
                            height: 25.5 / 17,
                          ),
                        ),
                      ),
                      Positioned(
                        left:
                            (metrics.canvasWidth - metrics.failureBodyWidth) /
                            2,
                        top: metrics.failureBodyTop,
                        width: metrics.failureBodyWidth,
                        child: Text(
                          failureBody,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            textStyle: theme.textTheme.bodyMedium,
                            color: bodyColor,
                            fontSize: metrics.failureBodySize,
                            fontWeight: FontWeight.w400,
                            height: 19.5 / 12,
                          ),
                        ),
                      ),
                      Positioned(
                        left: metrics.sideInset,
                        top: metrics.checkCardTop,
                        width: metrics.canvasWidth - (metrics.sideInset * 2),
                        child: Container(
                          height: metrics.checkCardHeight,
                          decoration: BoxDecoration(
                            color: surfaceColor,
                            borderRadius: BorderRadius.circular(
                              metrics.checkCardRadius,
                            ),
                            border: Border.all(color: surfaceBorderColor),
                            boxShadow: surfaceShadow,
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                left: metrics.checkCardInset,
                                top: metrics.checkHeadingTop,
                                child: Text(
                                  'THINGS TO CHECK',
                                  style: GoogleFonts.inter(
                                    textStyle: theme.textTheme.labelMedium,
                                    color: mutedHeadingColor,
                                    fontSize: metrics.checkTitleSize,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing:
                                        metrics.checkTitleLetterSpacing,
                                    height: 15 / 10,
                                  ),
                                ),
                              ),
                              Positioned(
                                left: metrics.checkCardInset,
                                top: metrics.checkRow1Top,
                                right: metrics.checkCardInset,
                                child: _FailureCheckRow(
                                  metrics: metrics,
                                  number: '1',
                                  badgeColor: badgeColor,
                                  badgeTextColor: badgeTextColor,
                                  bodyColor: checklistTextColor,
                                  text:
                                      'Camera is powered on and\nconnected to Wi-Fi',
                                ),
                              ),
                              Positioned(
                                left: metrics.checkCardInset,
                                top: metrics.checkRow2Top,
                                right: metrics.checkCardInset,
                                child: _FailureCheckRow(
                                  metrics: metrics,
                                  number: '2',
                                  badgeColor: badgeColor,
                                  badgeTextColor: badgeTextColor,
                                  bodyColor: checklistTextColor,
                                  text:
                                      'Your phone is on the same\nnetwork or has internet',
                                ),
                              ),
                              Positioned(
                                left: metrics.checkCardInset,
                                top: metrics.checkRow3Top,
                                right: metrics.checkCardInset,
                                child: _FailureCheckRow(
                                  metrics: metrics,
                                  number: '3',
                                  badgeColor: badgeColor,
                                  badgeTextColor: badgeTextColor,
                                  bodyColor: checklistTextColor,
                                  text: 'The relay device is running',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: metrics.sideInset,
                        top: metrics.tryAgainTop,
                        width: metrics.canvasWidth - (metrics.sideInset * 2),
                        height: metrics.tryAgainHeight,
                        child: FilledButton(
                          onPressed: _retryConnection,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF8BB3EE),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                metrics.tryAgainRadius,
                              ),
                            ),
                          ),
                          child: Text(
                            actionLabel,
                            style: GoogleFonts.inter(
                              textStyle: theme.textTheme.labelLarge,
                              color: Colors.white,
                              fontSize: metrics.tryAgainSize,
                              fontWeight: FontWeight.w600,
                              letterSpacing: metrics.tryAgainLetterSpacing,
                              height: 18 / 12,
                            ),
                          ),
                        ),
                      ),
                      if (!paused)
                        Positioned(
                          left:
                              (metrics.canvasWidth - metrics.retryRowWidth) / 2,
                          top: metrics.retryRowTop,
                          width: metrics.retryRowWidth,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: metrics.retrySpinnerSize,
                                height: metrics.retrySpinnerSize,
                                child: CircularProgressIndicator(
                                  strokeWidth: metrics.retrySpinnerStroke,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        Color(0xFF8BB3EE),
                                      ),
                                ),
                              ),
                              SizedBox(width: metrics.retrySpinnerGap),
                              Text(
                                'Retrying in 5s...',
                                style: GoogleFonts.inter(
                                  textStyle: theme.textTheme.bodyMedium,
                                  color: bodyColor,
                                  fontSize: metrics.retryLabelSize,
                                  fontWeight: FontWeight.w400,
                                  height: 16.5 / 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Positioned(
                        left:
                            (metrics.canvasWidth - metrics.backLabelWidth) / 2,
                        top: backLabelTop,
                        width: metrics.backLabelWidth,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap:
                              paused
                                  ? () => unawaited(_closeLivestream())
                                  : () => Navigator.of(context).maybePop(),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: 4 * metrics.scale,
                            ),
                            child: Text(
                              closeLabel,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                textStyle: theme.textTheme.bodyMedium,
                                color: bodyColor,
                                fontSize: metrics.backLabelSize,
                                fontWeight: FontWeight.w400,
                                height: 16.5 / 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPreviewStream() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = 16 / 9;
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        double videoWidth = screenWidth;
        double videoHeight = videoWidth / ratio;

        if (videoHeight > screenHeight) {
          videoHeight = screenHeight;
          videoWidth = videoHeight * ratio;
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: videoWidth,
              height: videoHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildPreviewMedia(),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.08),
                            Colors.black.withValues(alpha: 0.18),
                            Colors.black.withValues(alpha: 0.34),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 24,
              child: const SeclusoStatusChip(
                label: 'Live · end-to-end encrypted',
                icon: Icons.lock_outline,
                color: SeclusoColors.success,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ChunkFetchSnapshot {
  const _ChunkFetchSnapshot({
    required this.chunkNumber,
    required this.startedAtMs,
    required this.completedAtMs,
    required this.result,
  });

  final int chunkNumber;
  final int startedAtMs;
  final int completedAtMs;
  final Result<Uint8List> result;
}

class _LivestreamWorkingBackButton extends StatelessWidget {
  const _LivestreamWorkingBackButton({
    required this.size,
    required this.iconSize,
    required this.onTap,
  });

  final double size;
  final double iconSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Material(
          color: Colors.white.withValues(alpha: 0.1),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Center(
                child: SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: CustomPaint(
                    painter: _DesignLivestreamBackPainter(
                      Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LivestreamWorkingChip extends StatelessWidget {
  const _LivestreamWorkingChip({required this.metrics});

  final _LivestreamWorkingMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(metrics.e2eeHeight / 2),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          width: metrics.e2eeWidth,
          height: metrics.e2eeHeight,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(metrics.e2eeHeight / 2),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          padding: EdgeInsets.symmetric(horizontal: 10 * metrics.scale),
          child: Row(
            children: [
              SizedBox(
                width: metrics.e2eeIconSize,
                height: metrics.e2eeIconSize,
                child: CustomPaint(
                  painter: _DesignLivestreamLockPainter(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ),
              SizedBox(width: metrics.e2eeGap),
              Text(
                'E2EE',
                style: GoogleFonts.inter(
                  textStyle: Theme.of(context).textTheme.labelSmall,
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: metrics.e2eeLabelSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: metrics.e2eeLetterSpacing,
                  height: 12 / 8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LivestreamWorkingControlPanel extends StatelessWidget {
  const _LivestreamWorkingControlPanel({
    required this.metrics,
    required this.showDevOnlyControls,
    required this.onBackThirty,
    required this.onMute,
    required this.onStop,
    required this.onPhoto,
  });

  final _LivestreamWorkingMetrics metrics;
  final bool showDevOnlyControls;
  final VoidCallback onBackThirty;
  final VoidCallback onMute;
  final VoidCallback onStop;
  final VoidCallback onPhoto;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(metrics.controlPanelRadius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(metrics.controlPanelRadius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Stack(
            children: [
              if (showDevOnlyControls)
                Positioned(
                  left: metrics.controlButton1Left,
                  top: metrics.controlButtonTop,
                  child: _LivestreamWorkingRoundButton(
                    width: metrics.controlButtonWidth,
                    height: metrics.controlButtonHeight,
                    borderRadius: metrics.controlButtonHeight / 2,
                    onTap: onBackThirty,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: metrics.controlReplayIconSize,
                          height: metrics.controlReplayIconSize,
                          child: CustomPaint(
                            painter: _DesignLivestreamReplayPainter(
                              Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        SizedBox(height: 1.5 * metrics.scale),
                        Text(
                          '30',
                          style: GoogleFonts.inter(
                            textStyle: Theme.of(context).textTheme.labelSmall,
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: metrics.controlLabelSize,
                            fontWeight: FontWeight.w700,
                            height: 10.5 / 7,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (showDevOnlyControls)
                Positioned(
                  left: metrics.controlButton2Left,
                  top: metrics.controlButtonTop,
                  child: _LivestreamWorkingRoundButton(
                    width: metrics.controlButtonWidth,
                    height: metrics.controlButtonHeight,
                    borderRadius: metrics.controlButtonHeight / 2,
                    onTap: onMute,
                    child: SizedBox(
                      width: metrics.controlMuteIconSize,
                      height: metrics.controlMuteIconSize,
                      child: CustomPaint(
                        painter: _DesignLivestreamMicOffPainter(
                          Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: metrics.stopButtonLeft,
                top: metrics.stopButtonTop,
                child: _LivestreamWorkingRoundButton(
                  width: metrics.stopButtonWidth,
                  height: metrics.stopButtonHeight,
                  borderRadius: metrics.stopButtonHeight / 2,
                  onTap: onStop,
                  fillColor: Colors.white,
                  borderColor: Colors.transparent,
                  child: Container(
                    width: metrics.stopSquareSize,
                    height: metrics.stopSquareSize,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(2 * metrics.scale),
                    ),
                  ),
                ),
              ),
              if (showDevOnlyControls)
                Positioned(
                  left: metrics.controlButton4Left,
                  top: metrics.controlButtonTop,
                  child: _LivestreamWorkingRoundButton(
                    width: metrics.controlButtonWidth,
                    height: metrics.controlButtonHeight,
                    borderRadius: metrics.controlButtonHeight / 2,
                    onTap: onPhoto,
                    child: SizedBox(
                      width: metrics.controlCameraIconSize,
                      height: metrics.controlCameraIconSize,
                      child: CustomPaint(
                        painter: _DesignLivestreamCameraPainter(
                          Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LivestreamWorkingRoundButton extends StatelessWidget {
  const _LivestreamWorkingRoundButton({
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.onTap,
    required this.child,
    this.fillColor,
    this.borderColor,
  });

  final double width;
  final double height;
  final double borderRadius;
  final VoidCallback onTap;
  final Widget child;
  final Color? fillColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: onTap,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: fillColor ?? Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: borderColor ?? Colors.white.withValues(alpha: 0.04),
            ),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

class _LivestreamCoverMedia extends StatelessWidget {
  const _LivestreamCoverMedia({required this.aspectRatio, required this.child});

  final double aspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final targetWidth = constraints.maxWidth;
        final targetHeight = constraints.maxHeight;
        final targetAspect = targetWidth / targetHeight;
        final safeAspect = aspectRatio <= 0 ? (16 / 9) : aspectRatio;

        double mediaWidth;
        double mediaHeight;
        if (safeAspect > targetAspect) {
          mediaHeight = targetHeight;
          mediaWidth = mediaHeight * safeAspect;
        } else {
          mediaWidth = targetWidth;
          mediaHeight = mediaWidth / safeAspect;
        }

        return ClipRect(
          child: Center(
            child: SizedBox(
              width: mediaWidth,
              height: mediaHeight,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _LivestreamLoadingMedia extends StatelessWidget {
  const _LivestreamLoadingMedia({
    required this.orbitValue,
    required this.accentValue,
  });

  final double orbitValue;
  final double accentValue;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF0A0A0A)),
      child: Center(
        child: SizedBox(
          width: 104,
          height: 104,
          child: _LivestreamVaultLoadingArt(
            size: 104,
            orbitValue: orbitValue,
            accentValue: accentValue,
          ),
        ),
      ),
    );
  }
}

class _LivestreamVaultLoadingArt extends StatelessWidget {
  const _LivestreamVaultLoadingArt({
    required this.size,
    required this.orbitValue,
    required this.accentValue,
  });

  final double size;
  final double orbitValue;
  final double accentValue;

  double _shimmerOffset(double travel) {
    return math.sin(accentValue * math.pi * 2) * travel;
  }

  @override
  Widget build(BuildContext context) {
    final amber = const Color(0xFFB45309);
    final shieldSize = size * (52 / 80);
    final shimmerWidth = size * 2;
    final orbitRadius = size * (28 / 80);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: _LivestreamVaultOrbitParticle(
              progress: orbitValue * 1.5,
              radius: orbitRadius,
              size: size * (1 / 80),
              color: amber.withValues(alpha: 0.4),
            ),
          ),
          Positioned.fill(
            child: _LivestreamVaultOrbitParticle(
              progress: -orbitValue,
              radius: orbitRadius,
              size: size * (0.5 / 80),
              color: amber.withValues(alpha: 0.25),
            ),
          ),
          Positioned.fill(
            child: _LivestreamVaultOrbitParticle(
              progress: orbitValue * 1.2 + 0.3,
              radius: orbitRadius,
              size: size * (0.5 / 80),
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
          Positioned.fill(
            child: ClipOval(
              child: Transform.translate(
                offset: Offset(_shimmerOffset(size), 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: shimmerWidth,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.06),
                          Colors.white.withValues(alpha: 0),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: size * (40 / 80) - shieldSize / 2,
            top: size * (13 / 80),
            child: SizedBox(
              width: shieldSize,
              height: shieldSize,
              child: CustomPaint(painter: _LivestreamVaultShieldPainter()),
            ),
          ),
        ],
      ),
    );
  }
}

class _LivestreamVaultOrbitParticle extends StatelessWidget {
  const _LivestreamVaultOrbitParticle({
    required this.progress,
    required this.radius,
    required this.size,
    required this.color,
  });

  final double progress;
  final double radius;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final angle = progress * math.pi * 2;
    return SizedBox.expand(
      child: Transform.rotate(
        angle: angle,
        alignment: Alignment.center,
        child: Transform.translate(
          offset: Offset(radius, 0),
          child: Transform.rotate(
            angle: -angle,
            alignment: Alignment.center,
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LivestreamVaultShieldPainter extends CustomPainter {
  const _LivestreamVaultShieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final amber = const Color(0xFFB45309);
    final outerPath =
        Path()
          ..moveTo(size.width * 0.5, size.height * 0.08)
          ..cubicTo(
            size.width * 0.72,
            size.height * 0.16,
            size.width * 0.84,
            size.height * 0.19,
            size.width * 0.84,
            size.height * 0.23,
          )
          ..lineTo(size.width * 0.84, size.height * 0.53)
          ..cubicTo(
            size.width * 0.84,
            size.height * 0.78,
            size.width * 0.66,
            size.height * 0.92,
            size.width * 0.5,
            size.height * 1.03,
          )
          ..cubicTo(
            size.width * 0.34,
            size.height * 0.92,
            size.width * 0.16,
            size.height * 0.78,
            size.width * 0.16,
            size.height * 0.53,
          )
          ..lineTo(size.width * 0.16, size.height * 0.23)
          ..cubicTo(
            size.width * 0.16,
            size.height * 0.19,
            size.width * 0.28,
            size.height * 0.16,
            size.width * 0.5,
            size.height * 0.08,
          )
          ..close();
    final innerPath =
        Path()
          ..moveTo(size.width * 0.5, size.height * 0.15)
          ..cubicTo(
            size.width * 0.68,
            size.height * 0.22,
            size.width * 0.77,
            size.height * 0.24,
            size.width * 0.77,
            size.height * 0.28,
          )
          ..lineTo(size.width * 0.77, size.height * 0.53)
          ..cubicTo(
            size.width * 0.77,
            size.height * 0.73,
            size.width * 0.62,
            size.height * 0.84,
            size.width * 0.5,
            size.height * 0.92,
          )
          ..cubicTo(
            size.width * 0.38,
            size.height * 0.84,
            size.width * 0.23,
            size.height * 0.73,
            size.width * 0.23,
            size.height * 0.53,
          )
          ..lineTo(size.width * 0.23, size.height * 0.28)
          ..cubicTo(
            size.width * 0.23,
            size.height * 0.24,
            size.width * 0.32,
            size.height * 0.22,
            size.width * 0.5,
            size.height * 0.15,
          )
          ..close();
    canvas.drawPath(
      outerPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = amber.withValues(alpha: 0.06)
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      outerPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * (0.8 / 52)
        ..color = amber.withValues(alpha: 0.3)
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      innerPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * (0.4 / 52)
        ..color = amber.withValues(alpha: 0.15)
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.48),
      size.width * (1.5 / 52),
      Paint()
        ..style = PaintingStyle.fill
        ..color = amber.withValues(alpha: 0.2)
        ..isAntiAlias = true,
    );
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.48),
      size.width * (1.5 / 52),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * (0.5 / 52)
        ..color = amber.withValues(alpha: 0.4)
        ..isAntiAlias = true,
    );
    final stemRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.62),
        width: size.width * (1.2 / 52),
        height: size.height * (6.5 / 52),
      ),
      Radius.circular(size.width * (0.6 / 52)),
    );
    canvas.drawRRect(
      stemRect,
      Paint()
        ..style = PaintingStyle.fill
        ..color = amber.withValues(alpha: 0.2)
        ..isAntiAlias = true,
    );
    canvas.drawRRect(
      stemRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * (0.5 / 52)
        ..color = amber.withValues(alpha: 0.4)
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _LivestreamVaultShieldPainter oldDelegate) =>
      false;
}

class _DesignLivestreamBackPainter extends CustomPainter {
  const _DesignLivestreamBackPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * (1.33333 / 16)
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
    final path =
        Path()
          ..moveTo(size.width * (10 / 16), size.height * (12 / 16))
          ..lineTo(size.width * (6 / 16), size.height * (8 / 16))
          ..lineTo(size.width * (10 / 16), size.height * (4 / 16));
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _DesignLivestreamBackPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DesignLivestreamLockPainter extends CustomPainter {
  const _DesignLivestreamLockPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * (1.04167 / 10);
    final stroke =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * (1.25 / 10),
        size.height * (4.58333 / 10),
        size.width * (7.5 / 10),
        size.height * (4.58334 / 10),
      ),
      Radius.circular(size.width * (0.83333 / 10)),
    );
    canvas.drawRRect(body, stroke);

    final shackle =
        Path()
          ..moveTo(size.width * (2.91667 / 10), size.height * (4.58333 / 10))
          ..lineTo(size.width * (2.91667 / 10), size.height * (2.91667 / 10))
          ..arcToPoint(
            Offset(size.width * (7.08333 / 10), size.height * (2.91667 / 10)),
            radius: Radius.circular(size.width * (2.08333 / 10)),
            clockwise: true,
          )
          ..lineTo(size.width * (7.08333 / 10), size.height * (4.58333 / 10));
    canvas.drawPath(shackle, stroke);
  }

  @override
  bool shouldRepaint(covariant _DesignLivestreamLockPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DesignLivestreamReplayPainter extends CustomPainter {
  const _DesignLivestreamReplayPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.12
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;

    final arcRect = Rect.fromCircle(
      center: Offset(size.width * 0.52, size.height * 0.52),
      radius: size.width * 0.28,
    );
    canvas.drawArc(arcRect, math.pi * 0.15, math.pi * 1.65, false, stroke);

    final path =
        Path()
          ..moveTo(size.width * 0.22, size.height * 0.31)
          ..lineTo(size.width * 0.22, size.height * 0.08)
          ..lineTo(size.width * 0.41, size.height * 0.22);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _DesignLivestreamReplayPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DesignLivestreamMicOffPainter extends CustomPainter {
  const _DesignLivestreamMicOffPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.1
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;

    final capsule = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.34,
        size.height * 0.14,
        size.width * 0.32,
        size.height * 0.46,
      ),
      Radius.circular(size.width * 0.16),
    );
    canvas.drawRRect(capsule, stroke);

    final stem =
        Path()
          ..moveTo(size.width * 0.5, size.height * 0.6)
          ..lineTo(size.width * 0.5, size.height * 0.78)
          ..moveTo(size.width * 0.36, size.height * 0.84)
          ..lineTo(size.width * 0.64, size.height * 0.84)
          ..moveTo(size.width * 0.24, size.height * 0.47)
          ..arcToPoint(
            Offset(size.width * 0.76, size.height * 0.47),
            radius: Radius.circular(size.width * 0.26),
            clockwise: true,
          );
    canvas.drawPath(stem, stroke);

    canvas.drawLine(
      Offset(size.width * 0.2, size.height * 0.2),
      Offset(size.width * 0.8, size.height * 0.8),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _DesignLivestreamMicOffPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DesignLivestreamCameraPainter extends CustomPainter {
  const _DesignLivestreamCameraPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.1
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.12,
        size.height * 0.24,
        size.width * 0.76,
        size.height * 0.52,
      ),
      Radius.circular(size.width * 0.1),
    );
    canvas.drawRRect(body, stroke);
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.5),
      size.width * 0.16,
      stroke,
    );

    final topBump =
        Path()
          ..moveTo(size.width * 0.28, size.height * 0.24)
          ..lineTo(size.width * 0.38, size.height * 0.12)
          ..lineTo(size.width * 0.58, size.height * 0.12)
          ..lineTo(size.width * 0.68, size.height * 0.24);
    canvas.drawPath(topBump, stroke);
  }

  @override
  bool shouldRepaint(covariant _DesignLivestreamCameraPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _LivestreamWorkingMetrics {
  const _LivestreamWorkingMetrics({
    required this.scale,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.bottomPadding,
    required this.backButtonLeft,
    required this.backButtonTop,
    required this.backButtonSize,
    required this.backButtonIconSize,
    required this.headerTitleLeft,
    required this.headerTitleTop,
    required this.headerTitleWidth,
    required this.headerTitleSize,
    required this.liveDotLeft,
    required this.liveDotTop,
    required this.liveDotSize,
    required this.liveLabelLeft,
    required this.liveLabelTop,
    required this.liveLabelSize,
    required this.liveLabelLetterSpacing,
    required this.e2eeTop,
    required this.e2eeRight,
    required this.e2eeWidth,
    required this.e2eeHeight,
    required this.e2eeIconSize,
    required this.e2eeLabelSize,
    required this.e2eeLetterSpacing,
    required this.e2eeGap,
    required this.videoLeft,
    required this.videoTop,
    required this.videoWidth,
    required this.videoHeight,
    required this.videoRadius,
    required this.controlPanelLeft,
    required this.controlPanelTop,
    required this.controlPanelWidth,
    required this.controlPanelHeight,
    required this.controlPanelRadius,
    required this.controlButtonTop,
    required this.controlButtonWidth,
    required this.controlButtonHeight,
    required this.controlButton1Left,
    required this.controlButton2Left,
    required this.controlButton4Left,
    required this.controlReplayIconSize,
    required this.controlMuteIconSize,
    required this.controlCameraIconSize,
    required this.controlLabelSize,
    required this.stopButtonLeft,
    required this.stopButtonTop,
    required this.stopButtonWidth,
    required this.stopButtonHeight,
    required this.stopSquareSize,
    required this.micLabelTop,
    required this.micLabelSize,
    required this.footerTop,
    required this.footerWidth,
    required this.footerSize,
    required this.footerLetterSpacing,
  });

  final double scale;
  final double canvasWidth;
  final double canvasHeight;
  final double bottomPadding;
  final double backButtonLeft;
  final double backButtonTop;
  final double backButtonSize;
  final double backButtonIconSize;
  final double headerTitleLeft;
  final double headerTitleTop;
  final double headerTitleWidth;
  final double headerTitleSize;
  final double liveDotLeft;
  final double liveDotTop;
  final double liveDotSize;
  final double liveLabelLeft;
  final double liveLabelTop;
  final double liveLabelSize;
  final double liveLabelLetterSpacing;
  final double e2eeTop;
  final double e2eeRight;
  final double e2eeWidth;
  final double e2eeHeight;
  final double e2eeIconSize;
  final double e2eeLabelSize;
  final double e2eeLetterSpacing;
  final double e2eeGap;
  final double videoLeft;
  final double videoTop;
  final double videoWidth;
  final double videoHeight;
  final double videoRadius;
  final double controlPanelLeft;
  final double controlPanelTop;
  final double controlPanelWidth;
  final double controlPanelHeight;
  final double controlPanelRadius;
  final double controlButtonTop;
  final double controlButtonWidth;
  final double controlButtonHeight;
  final double controlButton1Left;
  final double controlButton2Left;
  final double controlButton4Left;
  final double controlReplayIconSize;
  final double controlMuteIconSize;
  final double controlCameraIconSize;
  final double controlLabelSize;
  final double stopButtonLeft;
  final double stopButtonTop;
  final double stopButtonWidth;
  final double stopButtonHeight;
  final double stopSquareSize;
  final double micLabelTop;
  final double micLabelSize;
  final double footerTop;
  final double footerWidth;
  final double footerSize;
  final double footerLetterSpacing;

  factory _LivestreamWorkingMetrics.forViewport(
    double width,
    double fullScreenHeight,
  ) {
    final widthScale = width / 290;
    final heightScale = fullScreenHeight / 652;
    final scale = math.min(widthScale, heightScale);
    double scaled(double value) => value * scale;
    return _LivestreamWorkingMetrics(
      scale: scale,
      canvasWidth: scaled(290),
      canvasHeight: scaled(652),
      bottomPadding: scaled(12),
      backButtonLeft: scaled(20),
      backButtonTop: scaled(56),
      backButtonSize: scaled(36),
      backButtonIconSize: scaled(22),
      headerTitleLeft: scaled(100.27),
      headerTitleTop: scaled(56.5),
      headerTitleWidth: scaled(110),
      headerTitleSize: scaled(13),
      liveDotLeft: scaled(116.08),
      liveDotTop: scaled(81.75),
      liveDotSize: scaled(6),
      liveLabelLeft: scaled(128.08),
      liveLabelTop: scaled(78),
      liveLabelSize: scaled(9),
      liveLabelLetterSpacing: scaled(0.9),
      e2eeTop: scaled(63),
      e2eeRight: scaled(20),
      e2eeWidth: scaled(59.12),
      e2eeHeight: scaled(22),
      e2eeIconSize: scaled(10),
      e2eeLabelSize: scaled(8),
      e2eeLetterSpacing: scaled(0.4),
      e2eeGap: scaled(6),
      videoLeft: scaled(8),
      videoTop: scaled(228.44),
      videoWidth: scaled(274),
      videoHeight: scaled(154.13),
      videoRadius: scaled(12),
      controlPanelLeft: scaled(20),
      controlPanelTop: scaled(507),
      controlPanelWidth: scaled(250),
      controlPanelHeight: scaled(82),
      controlPanelRadius: scaled(16),
      controlButtonTop: scaled(19),
      controlButtonWidth: scaled(35.58),
      controlButtonHeight: scaled(44),
      controlButton1Left: scaled(13),
      controlButton2Left: scaled(72.59),
      controlButton4Left: scaled(201.42),
      controlReplayIconSize: scaled(16),
      controlMuteIconSize: scaled(18),
      controlCameraIconSize: scaled(18),
      controlLabelSize: scaled(7),
      stopButtonLeft: scaled(132.15),
      stopButtonTop: scaled(13),
      stopButtonWidth: scaled(45.27),
      stopButtonHeight: scaled(56),
      stopSquareSize: scaled(20),
      micLabelTop: scaled(598.5),
      micLabelSize: scaled(9),
      footerTop: scaled(614.5),
      footerWidth: scaled(218.14),
      footerSize: scaled(9),
      footerLetterSpacing: scaled(0.9),
    );
  }
}

class _FailureBackButton extends StatelessWidget {
  const _FailureBackButton({
    required this.size,
    required this.iconSize,
    required this.fillColor,
    required this.iconColor,
    required this.onTap,
  });

  final double size;
  final double iconSize;
  final Color fillColor;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fillColor,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: iconSize,
            color: iconColor,
          ),
        ),
      ),
    );
  }
}

class _FailureCheckRow extends StatelessWidget {
  const _FailureCheckRow({
    required this.metrics,
    required this.number,
    required this.badgeColor,
    required this.badgeTextColor,
    required this.bodyColor,
    required this.text,
  });

  final _LivestreamFailureMetrics metrics;
  final String number;
  final Color badgeColor;
  final Color badgeTextColor;
  final Color bodyColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: metrics.checkBadgeSize,
          height: metrics.checkBadgeSize,
          decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            number,
            style: GoogleFonts.inter(
              textStyle: Theme.of(context).textTheme.labelSmall,
              color: badgeTextColor,
              fontSize: metrics.checkBadgeTextSize,
              fontWeight: FontWeight.w600,
              height: 12 / 8,
            ),
          ),
        ),
        SizedBox(width: metrics.checkBadgeGap),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              textStyle: Theme.of(context).textTheme.bodyMedium,
              color: bodyColor,
              fontSize: metrics.checkBodySize,
              fontWeight: FontWeight.w400,
              height: 17.88 / 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _LivestreamFailureMetrics {
  const _LivestreamFailureMetrics({
    required this.scale,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.sideInset,
    required this.topInset,
    required this.bottomInset,
    required this.backButtonLeft,
    required this.headerTop,
    required this.headerHeight,
    required this.backButtonSize,
    required this.backIconSize,
    required this.headerTextLeft,
    required this.headerTitleSize,
    required this.headerTitleTop,
    required this.headerSubtitleSize,
    required this.headerSubtitleTop,
    required this.errorIconTop,
    required this.errorIconCardSize,
    required this.errorIconCardRadius,
    required this.errorIconSize,
    required this.failureTitleTop,
    required this.failureTitleWidth,
    required this.failureTitleSize,
    required this.failureBodyTop,
    required this.failureBodyWidth,
    required this.failureBodySize,
    required this.checkCardTop,
    required this.checkCardHeight,
    required this.checkCardRadius,
    required this.checkCardInset,
    required this.checkHeadingTop,
    required this.checkTitleSize,
    required this.checkTitleLetterSpacing,
    required this.checkRow1Top,
    required this.checkRow2Top,
    required this.checkRow3Top,
    required this.checkBadgeSize,
    required this.checkBadgeTextSize,
    required this.checkBadgeGap,
    required this.checkBodySize,
    required this.tryAgainTop,
    required this.tryAgainHeight,
    required this.tryAgainRadius,
    required this.tryAgainSize,
    required this.tryAgainLetterSpacing,
    required this.retryRowTop,
    required this.retryRowWidth,
    required this.retrySpinnerSize,
    required this.retrySpinnerStroke,
    required this.retrySpinnerGap,
    required this.retryLabelSize,
    required this.backLabelTop,
    required this.backLabelWidth,
    required this.backLabelSize,
  });

  final double scale;
  final double canvasWidth;
  final double canvasHeight;
  final double sideInset;
  final double topInset;
  final double bottomInset;
  final double backButtonLeft;
  final double headerTop;
  final double headerHeight;
  final double backButtonSize;
  final double backIconSize;
  final double headerTextLeft;
  final double headerTitleSize;
  final double headerTitleTop;
  final double headerSubtitleSize;
  final double headerSubtitleTop;
  final double errorIconTop;
  final double errorIconCardSize;
  final double errorIconCardRadius;
  final double errorIconSize;
  final double failureTitleTop;
  final double failureTitleWidth;
  final double failureTitleSize;
  final double failureBodyTop;
  final double failureBodyWidth;
  final double failureBodySize;
  final double checkCardTop;
  final double checkCardHeight;
  final double checkCardRadius;
  final double checkCardInset;
  final double checkHeadingTop;
  final double checkTitleSize;
  final double checkTitleLetterSpacing;
  final double checkRow1Top;
  final double checkRow2Top;
  final double checkRow3Top;
  final double checkBadgeSize;
  final double checkBadgeTextSize;
  final double checkBadgeGap;
  final double checkBodySize;
  final double tryAgainTop;
  final double tryAgainHeight;
  final double tryAgainRadius;
  final double tryAgainSize;
  final double tryAgainLetterSpacing;
  final double retryRowTop;
  final double retryRowWidth;
  final double retrySpinnerSize;
  final double retrySpinnerStroke;
  final double retrySpinnerGap;
  final double retryLabelSize;
  final double backLabelTop;
  final double backLabelWidth;
  final double backLabelSize;

  factory _LivestreamFailureMetrics.forViewport(
    double width,
    double fullScreenHeight,
  ) {
    final widthScale = width / 290;
    final heightScale = fullScreenHeight / 652;
    final scale = math.min(widthScale, heightScale);
    final canvasWidth = 290 * scale;
    double scaled(double value) => value * scale;
    return _LivestreamFailureMetrics(
      scale: scale,
      canvasWidth: canvasWidth,
      canvasHeight: scaled(652),
      sideInset: scaled(24),
      topInset: 0,
      bottomInset: scaled(18),
      backButtonLeft: scaled(20),
      headerTop: scaled(22),
      headerHeight: scaled(48),
      backButtonSize: scaled(32),
      backIconSize: scaled(16),
      headerTextLeft: scaled(64),
      headerTitleSize: scaled(18),
      headerTitleTop: scaled(12),
      headerSubtitleSize: scaled(10),
      headerSubtitleTop: scaled(48),
      errorIconTop: scaled(96),
      errorIconCardSize: scaled(64),
      errorIconCardRadius: scaled(16),
      errorIconSize: scaled(28),
      failureTitleTop: scaled(192),
      failureTitleWidth: scaled(150.224),
      failureTitleSize: scaled(17),
      failureBodyTop: scaled(228),
      failureBodyWidth: scaled(213),
      failureBodySize: scaled(12),
      checkCardTop: scaled(276.5),
      checkCardHeight: scaled(168.5),
      checkCardRadius: scaled(12),
      checkCardInset: scaled(16),
      checkHeadingTop: scaled(16),
      checkTitleSize: scaled(10),
      checkTitleLetterSpacing: scaled(1),
      checkRow1Top: scaled(43),
      checkRow2Top: scaled(88.75),
      checkRow3Top: scaled(134.5),
      checkBadgeSize: scaled(16),
      checkBadgeTextSize: scaled(8),
      checkBadgeGap: scaled(10),
      checkBodySize: scaled(11),
      tryAgainTop: scaled(469),
      tryAgainHeight: scaled(42),
      tryAgainRadius: scaled(12),
      tryAgainSize: scaled(12),
      tryAgainLetterSpacing: scaled(0.6),
      retryRowTop: scaled(537),
      retryRowWidth: scaled(110),
      retrySpinnerSize: scaled(12),
      retrySpinnerStroke: scaled(1.6),
      retrySpinnerGap: scaled(8),
      retryLabelSize: scaled(11),
      backLabelTop: scaled(560),
      backLabelWidth: scaled(106.164),
      backLabelSize: scaled(11),
    );
  }
}
