// 插件 manifest 新增字段的解析测试（Phase 4.4 校外登录）。
//
// 这些字段是**纯新增**（老插件不写就回落默认值），所以除了新字段本身，
// 还要钉住"老 manifest 行为不变"这条向后兼容线。
import 'package:flutter_test/flutter_test.dart';
import 'package:my_schedule_app/runtime/plugin_manifest.dart';
import 'package:my_schedule_app/runtime/plugin_qr_login.dart';

void main() {
  group('PluginQrLogin', () {
    test('host 精确匹配 / 同主域子域匹配', () {
      const PluginQrLogin qr = PluginQrLogin(host: 'authserver.ncst.edu.cn');
      expect(qr.matchesHost('https://authserver.ncst.edu.cn/authserver/login'),
          isTrue);
      expect(qr.matchesHost('https://cas.authserver.ncst.edu.cn/login'), isTrue);
      expect(qr.matchesHost('https://authserver.ncst.edu.cn.evil.com/'), isFalse);
      expect(qr.matchesHost('https://evilncst.edu.cn/'), isFalse);
      expect(qr.matchesHost(''), isFalse);
    });

    test('tryParse 缺 host / 不是对象时返回 null', () {
      expect(PluginQrLogin.tryParse(null), isNull);
      expect(PluginQrLogin.tryParse('abc'), isNull);
      expect(PluginQrLogin.tryParse(<String, dynamic>{}), isNull);
      expect(
        PluginQrLogin.tryParse(<String, dynamic>{'host': '  '}),
        isNull,
      );
    });

    test('选择器有默认值', () {
      final PluginQrLogin? qr = PluginQrLogin.tryParse(
        <String, dynamic>{'host': 'authserver.ncst.edu.cn'},
      );
      expect(qr, isNotNull);
      expect(qr!.imageSelector, '#qr_img');
      expect(qr.uuidSelector, '#uuid');
      expect(qr.containerSelector, isEmpty);
    });
  });

  group('PluginManifest 校外登录字段', () {
    test('完整 JSON 能解析并 round-trip', () {
      final PluginManifest manifest = PluginManifest.fromJson(<String, dynamic>{
        'id': 'ncst-jwxt',
        'name': '华北理工大学教务系统',
        'version': '1.0.0',
        'loginUrl': 'https://xjw1.ncst.edu.cn/',
        'checkUrl': 'https://xjw1.ncst.edu.cn/student/courseSelect/index',
        'campusProbeUrl': 'https://xjw1.ncst.edu.cn/',
        'offCampusHost': 'webexp.ncst.edu.cn',
        'offCampusUserAgent': 'Mozilla/5.0 Desktop',
        'qrLogin': <String, dynamic>{
          'host': 'authserver.ncst.edu.cn',
          'containerSelector': '.ncst-qrcode',
          'imageSelector': '#qr_img',
          'uuidSelector': '#uuid',
        },
      });

      expect(manifest.campusProbeUrl, 'https://xjw1.ncst.edu.cn/');
      expect(manifest.offCampusHost, 'webexp.ncst.edu.cn');
      expect(manifest.offCampusUserAgent, 'Mozilla/5.0 Desktop');
      expect(manifest.qrLogin?.host, 'authserver.ncst.edu.cn');
      expect(manifest.qrLogin?.containerSelector, '.ncst-qrcode');

      final Map<String, dynamic> json = manifest.toJson();
      final PluginManifest again = PluginManifest.fromJson(json);
      expect(again.campusProbeUrl, manifest.campusProbeUrl);
      expect(again.offCampusHost, manifest.offCampusHost);
      expect(again.offCampusUserAgent, manifest.offCampusUserAgent);
      expect(again.qrLogin?.host, manifest.qrLogin?.host);
    });

    test('老 manifest 不写新字段时全部回落默认值', () {
      final PluginManifest manifest = PluginManifest.fromJson(<String, dynamic>{
        'id': 'old-plugin',
        'name': '旧插件',
      });
      expect(manifest.campusProbeUrl, isEmpty);
      expect(manifest.offCampusHost, isEmpty);
      expect(manifest.offCampusUserAgent, isEmpty);
      expect(manifest.qrLogin, isNull);
      expect(manifest.toJson().containsKey('qrLogin'), isFalse);
    });

    test('qrLogin 不是对象时忽略，不抛异常', () {
      final PluginManifest manifest = PluginManifest.fromJson(<String, dynamic>{
        'id': 'broken',
        'qrLogin': 'not-an-object',
      });
      expect(manifest.qrLogin, isNull);
    });
  });
}
