part of '../../main.dart';

class WorkoutMapPoint {
  const WorkoutMapPoint(this.lat, this.lng);

  final double lat;
  final double lng;
}

class WorkoutMapCard extends StatefulWidget {
  const WorkoutMapCard({
    super.key,
    required this.points,
    required this.privacyGranted,
    this.onRequestMap,
    this.height = 260,
    this.title = '实时路线',
  });

  final List<WorkoutMapPoint> points;
  final bool privacyGranted;
  final VoidCallback? onRequestMap;
  final double height;
  final String title;

  @override
  State<WorkoutMapCard> createState() => _WorkoutMapCardState();
}

class _WorkoutMapCardState extends State<WorkoutMapCard> {
  final fmap.MapController _controller = fmap.MapController();
  bool _controllerReady = false;
  bool _followCurrent = true;

  List<latlng.LatLng> get _mapPoints => widget.points
      .map((point) => latlng.LatLng(point.lat, point.lng))
      .toList(growable: false);

  @override
  void didUpdateWidget(covariant WorkoutMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_followCurrent && widget.points.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _moveToLatest());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _moveToLatest() {
    if (!_controllerReady || !mounted || widget.points.isEmpty) return;
    final point = widget.points.last;
    _controller.move(latlng.LatLng(point.lat, point.lng), 17);
  }

  @override
  Widget build(BuildContext context) {
    final points = _mapPoints;
    return Card(
      key: const Key('workout-map-card'),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.map_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (widget.privacyGranted)
                  IconButton(
                    key: const Key('workout-map-follow'),
                    tooltip: _followCurrent ? '停止跟随' : '跟随当前位置',
                    onPressed: () {
                      setState(() => _followCurrent = !_followCurrent);
                      if (_followCurrent) _moveToLatest();
                    },
                    icon: Icon(
                      _followCurrent
                          ? Icons.my_location
                          : Icons.location_searching,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: widget.height,
            width: double.infinity,
            child: points.isEmpty
                ? const _EmptyWorkoutMap()
                : widget.privacyGranted
                    ? fmap.FlutterMap(
                        mapController: _controller,
                        options: fmap.MapOptions(
                          initialCenter: points.last,
                          initialZoom: 17,
                          initialCameraFit: points.length < 2
                              ? null
                              : fmap.CameraFit.coordinates(
                                  coordinates: points,
                                  padding: const EdgeInsets.all(32),
                                  maxZoom: 18,
                                ),
                          minZoom: 3,
                          maxZoom: 19,
                          onMapReady: () {
                            _controllerReady = true;
                            if (_followCurrent && points.length < 2) {
                              _moveToLatest();
                            }
                          },
                          onPositionChanged: (_, hasGesture) {
                            if (hasGesture && _followCurrent) {
                              setState(() => _followCurrent = false);
                            }
                          },
                        ),
                        children: [
                          fmap.TileLayer(
                            urlTemplate: _mapTileUrl,
                            userAgentPackageName: 'com.fitloop.fitloop',
                            maxNativeZoom: 19,
                          ),
                          if (points.length >= 2)
                            fmap.PolylineLayer(
                              polylines: [
                                fmap.Polyline(
                                  points: points,
                                  strokeWidth: 6,
                                  color: const Color(0xFF1F8A70),
                                ),
                              ],
                            ),
                          fmap.MarkerLayer(
                            markers: [
                              _routeMarker(
                                point: points.first,
                                color: const Color(0xFF2563EB),
                                label: '起点',
                              ),
                              _routeMarker(
                                point: points.last,
                                color: const Color(0xFFEF4444),
                                label: '当前位置',
                              ),
                            ],
                          ),
                          const fmap.SimpleAttributionWidget(
                            source: Text('OpenStreetMap contributors'),
                          ),
                        ],
                      )
                    : _LocalTrackPreview(points: widget.points),
          ),
          if (!widget.privacyGranted)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '当前为不联网的本地轨迹预览；同意地图隐私说明后可显示道路底图。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    key: const Key('enable-map-button'),
                    onPressed: widget.onRequestMap,
                    child: const Text('启用底图'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  fmap.Marker _routeMarker({
    required latlng.LatLng point,
    required Color color,
    required String label,
  }) {
    return fmap.Marker(
      point: point,
      width: 34,
      height: 34,
      child: Semantics(
        label: label,
        child: Icon(Icons.location_on, size: 30, color: color),
      ),
    );
  }
}

class _EmptyWorkoutMap extends StatelessWidget {
  const _EmptyWorkoutMap();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF2F6F5),
      child: Center(child: Text('正在等待第一个有效定位点…')),
    );
  }
}

class _LocalTrackPreview extends StatelessWidget {
  const _LocalTrackPreview({required this.points});

  final List<WorkoutMapPoint> points;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const Key('local-track-preview'),
      painter: _TrackPreviewPainter(points),
      child: const SizedBox.expand(),
    );
  }
}

class _TrackPreviewPainter extends CustomPainter {
  _TrackPreviewPainter(this.points);

  final List<WorkoutMapPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFFF2F6F5);
    canvas.drawRect(Offset.zero & size, background);
    final grid = Paint()
      ..color = const Color(0xFFDDE8E4)
      ..strokeWidth = 1;
    for (var i = 1; i < 5; i++) {
      final x = size.width * i / 5;
      final y = size.height * i / 5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final minLat = points.map((point) => point.lat).reduce(min);
    final maxLat = points.map((point) => point.lat).reduce(max);
    final minLng = points.map((point) => point.lng).reduce(min);
    final maxLng = points.map((point) => point.lng).reduce(max);
    const padding = 24.0;
    final latSpan = max(maxLat - minLat, 0.00001);
    final lngSpan = max(maxLng - minLng, 0.00001);
    Offset project(WorkoutMapPoint point) => Offset(
          padding + (point.lng - minLng) / lngSpan * (size.width - padding * 2),
          padding +
              (maxLat - point.lat) / latSpan * (size.height - padding * 2),
        );
    final route = Path()
      ..moveTo(project(points.first).dx, project(points.first).dy);
    for (final point in points.skip(1)) {
      final offset = project(point);
      route.lineTo(offset.dx, offset.dy);
    }
    canvas.drawPath(
      route,
      Paint()
        ..color = const Color(0xFF1F8A70)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(
      project(points.first),
      7,
      Paint()..color = const Color(0xFF2563EB),
    );
    canvas.drawCircle(
      project(points.last),
      7,
      Paint()..color = const Color(0xFFEF4444),
    );
  }

  @override
  bool shouldRepaint(covariant _TrackPreviewPainter oldDelegate) =>
      oldDelegate.points != points;
}

class WorkoutTrackPage extends StatefulWidget {
  const WorkoutTrackPage({
    super.key,
    required this.api,
    required this.session,
    required this.record,
    required this.privacyGranted,
    this.onRequestMap,
  });

  final FitLoopApi api;
  final UserSession session;
  final SportRecord record;
  final bool privacyGranted;
  final Future<bool> Function()? onRequestMap;

  @override
  State<WorkoutTrackPage> createState() => _WorkoutTrackPageState();
}

class _WorkoutTrackPageState extends State<WorkoutTrackPage> {
  late Future<WorkoutTrack> _future;
  late bool _privacyGranted;

  @override
  void initState() {
    super.initState();
    _privacyGranted = widget.privacyGranted;
    _future = widget.api.workoutTrack(
      token: widget.session.token,
      recordId: widget.record.recordId,
    );
  }

  Future<void> _requestMap() async {
    final granted = await widget.onRequestMap?.call() ?? false;
    if (mounted && granted) {
      setState(() => _privacyGranted = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('路线 #${widget.record.recordId}')),
      body: FutureBuilder<WorkoutTrack>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(friendlyErrorMsg(snapshot.error)));
          }
          final track = snapshot.data;
          if (track == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final points = track.points
              .map((point) => WorkoutMapPoint(point.lat, point.lng))
              .toList(growable: false);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              WorkoutMapCard(
                points: points,
                privacyGranted: _privacyGranted,
                onRequestMap: widget.onRequestMap == null
                    ? null
                    : () => unawaited(_requestMap()),
                height: 360,
                title: '历史路线',
              ),
              _MetricCard(
                label: '轨迹点',
                value: '${points.length} 个',
                icon: Icons.route_outlined,
              ),
              _MetricCard(
                label: '坐标来源',
                value: '${track.coordinateSystem} 原始定位，仅本人可见',
                icon: Icons.privacy_tip_outlined,
              ),
            ],
          );
        },
      ),
    );
  }
}
