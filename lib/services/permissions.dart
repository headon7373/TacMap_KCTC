import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// 권한 확인 결과. 화면에서 무엇을 안내할지 결정하는 데 쓴다.
enum PermissionOutcome {
  ready,

  /// 폰의 위치(GPS) 자체가 꺼져 있다.
  locationServiceOff,

  /// 위치 권한을 거부했다. 이건 없으면 앱의 존재 이유가 없다.
  locationDenied,

  /// 위치 권한을 "다시 묻지 않음"으로 막았다. 설정에서 직접 켜야 한다.
  locationBlocked,

  /// 위치는 되지만 알림이 막혔다. 동작은 하되 화면을 끄면 끊길 수 있다.
  notificationDenied,
}

/// 게임에 필요한 권한을 순서대로 확인하고 요청한다.
///
/// - 위치: 없으면 팀에 내 위치를 보낼 수 없다. 필수.
/// - 알림: 안드로이드 13부터는 알림 권한이 있어야 포그라운드 서비스 알림이 뜬다.
///   이게 없으면 다른 앱(디스코드 등)을 앞에 띄웠을 때 위치 전송이 끊길 수 있다.
Future<PermissionOutcome> ensureGamePermissions() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    return PermissionOutcome.locationServiceOff;
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever) {
    return PermissionOutcome.locationBlocked;
  }
  if (permission == LocationPermission.denied) {
    return PermissionOutcome.locationDenied;
  }

  // 안드로이드 12 이하에서는 알림 권한 개념이 없어 항상 granted로 돌아온다.
  var notification = await Permission.notification.status;
  if (notification.isDenied) {
    notification = await Permission.notification.request();
  }
  if (!notification.isGranted) {
    return PermissionOutcome.notificationDenied;
  }

  return PermissionOutcome.ready;
}

/// 사용자에게 보여줄 안내 문구.
String permissionMessage(PermissionOutcome outcome) => switch (outcome) {
      PermissionOutcome.ready => '',
      PermissionOutcome.locationServiceOff =>
        '휴대폰의 위치(GPS)가 꺼져 있습니다. 상단 바에서 위치를 켜주세요.',
      PermissionOutcome.locationDenied =>
        '위치 권한이 없으면 팀에 내 위치를 보낼 수 없습니다.',
      PermissionOutcome.locationBlocked =>
        '위치 권한이 차단되어 있습니다. 설정 > 앱 > TacMap > 권한에서 허용해 주세요.',
      PermissionOutcome.notificationDenied =>
        '알림 권한이 없습니다. 다른 앱을 켜두면 위치 전송이 끊길 수 있습니다.',
    };

/// 이 상태로도 게임은 할 수 있는가. 알림만 없는 경우는 경고만 하고 진행한다.
bool canPlay(PermissionOutcome outcome) =>
    outcome == PermissionOutcome.ready ||
    outcome == PermissionOutcome.notificationDenied;

Future<void> openPermissionSettings() => openAppSettings();
