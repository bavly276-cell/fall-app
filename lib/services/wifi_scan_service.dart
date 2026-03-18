import 'package:wifi_scan/wifi_scan.dart';
import 'permission_manager.dart';

class WifiScanService {
  WifiScanService._();

  static Future<bool> ensureScanReady() async {
    final hasLocation = await PermissionManager.requestLocationPermission();
    if (!hasLocation) return false;

    final canStart = await WiFiScan.instance.canStartScan(askPermissions: true);
    return canStart == CanStartScan.yes;
  }

  static Future<bool> startScan() async {
    final ready = await ensureScanReady();
    if (!ready) return false;

    final ok = await WiFiScan.instance.startScan();
    return ok == true;
  }

  static Future<List<WiFiAccessPoint>> getResults() async {
    final canGet = await WiFiScan.instance.canGetScannedResults(
      askPermissions: true,
    );
    if (canGet != CanGetScannedResults.yes) return [];

    final results = await WiFiScan.instance.getScannedResults();
    return results;
  }
}
