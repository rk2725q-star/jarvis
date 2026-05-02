import 'package:flutter/services.dart';

class PlatformChannelService {
  static const MethodChannel _channel = 
      MethodChannel('com.aurora.player/platform');

  /// Sets screen brightness (0.0 - 1.0)
  /// Note: This is a WINDOW-level brightness overlay, not system-wide
  static Future<void> setScreenBrightness(double brightness) async {
    try {
      await _channel.invokeMethod('setBrightness', {
        'brightness': brightness.clamp(0.0, 1.0),
      });
    } on PlatformException catch (e) {
      throw PlatformException(
        code: 'BRIGHTNESS_ERROR',
        message: 'Failed to set brightness: ${e.message}',
      );
    }
  }

  /// Checks if the current display supports HDR playback
  static Future<HdrCapabilities> checkHdrSupport() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('checkHdrSupport');
      return HdrCapabilities(
        isHdrSupported: result?['isHdrSupported'] ?? false,
        supportedProfiles: List<String>.from(result?['profiles'] ?? []),
        maxLuminance: result?['maxLuminance']?.toDouble() ?? 0.0,
      );
    } catch (e) {
      return HdrCapabilities(isHdrSupported: false, supportedProfiles: [], maxLuminance: 0);
    }
  }

  /// Restores auto-brightness on exit
  static Future<void> resetBrightness() async {
    await _channel.invokeMethod('resetBrightness');
  }
}

class HdrCapabilities {
  final bool isHdrSupported;
  final List<String> supportedProfiles;
  final double maxLuminance;

  HdrCapabilities({
    required this.isHdrSupported,
    required this.supportedProfiles,
    required this.maxLuminance,
  });
}
