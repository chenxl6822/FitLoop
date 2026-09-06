import 'coord_transform.dart';

/// Xiangtan University main campus — default map center for campus mode.
const xtuCampusCenterLat = 27.882;
const xtuCampusCenterLng = 112.909;

const _tiandituToken = String.fromEnvironment(
  'FITLOOP_TIANDITU_TOKEN',
  defaultValue: '',
);

const _customTileUrl = String.fromEnvironment(
  'FITLOOP_MAP_TILE_URL',
  defaultValue: '',
);

const _mapCoordinateSystem = String.fromEnvironment(
  'FITLOOP_MAP_COORDINATE_SYSTEM',
  defaultValue: 'WGS84',
);

class MapConfig {
  const MapConfig._();

  static bool get hasConfiguredTiles =>
      _customTileUrl.isNotEmpty || _tiandituToken.isNotEmpty;

  static bool get usesTianditu =>
      _customTileUrl.isEmpty && _tiandituToken.isNotEmpty;

  static String get baseTileUrl {
    if (_customTileUrl.isNotEmpty) return _customTileUrl;
    if (_tiandituToken.isEmpty) return '';
    return 'https://t{s}.tianditu.gov.cn/vec_w/wmts?'
        'SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=vec&STYLE=default&'
        'TILEMATRIXSET=w&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$_tiandituToken';
  }

  static String get labelTileUrl {
    if (!usesTianditu) return '';
    return 'https://t{s}.tianditu.gov.cn/cva_w/wmts?'
        'SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=cva&STYLE=default&'
        'TILEMATRIXSET=w&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$_tiandituToken';
  }

  static String get imageryTileUrl {
    if (!usesTianditu) return '';
    return 'https://t{s}.tianditu.gov.cn/img_w/wmts?'
        'SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=img&STYLE=default&'
        'TILEMATRIXSET=w&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$_tiandituToken';
  }

  static String get imageryLabelTileUrl {
    if (!usesTianditu) return '';
    return 'https://t{s}.tianditu.gov.cn/cia_w/wmts?'
        'SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=cia&STYLE=default&'
        'TILEMATRIXSET=w&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$_tiandituToken';
  }

  static List<String> get tileSubdomains => const ['0', '1', '2', '3', '4', '5', '6', '7'];

  static String get attributionLabel {
    if (usesTianditu) return '天地图';
    if (_customTileUrl.contains('openstreetmap')) return 'OpenStreetMap contributors';
    return '地图数据';
  }

  /// Display coordinates for map rendering. Storage remains WGS84.
  static ({double lat, double lng}) displayCoordinate(double lat, double lng) {
    return displayCoordinateForSystem(lat, lng, _mapCoordinateSystem);
  }

  static ({double lat, double lng}) displayCoordinateForSystem(
    double lat,
    double lng,
    String coordinateSystem,
  ) {
    if (coordinateSystem.toUpperCase() != 'GCJ02') {
      return (lat: lat, lng: lng);
    }
    final gcj = CoordTransform.wgs84ToGcj02(lat, lng);
    return (lat: gcj.lat, lng: gcj.lng);
  }
}
