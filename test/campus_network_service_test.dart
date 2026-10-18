// 校园网 / 校外探测的分类逻辑测试。
//
// 真实网络无法在 flutter test 里稳定复现，所以这里只测纯函数
// `classifyCampusProbe`：它决定"去账号密码页"还是"去微信扫码页"，
// 判错的代价是用户看到错误的登录方式，值得用回归测试钉住。
import 'package:flutter_test/flutter_test.dart';
import 'package:my_schedule_app/services/campus_network_service.dart';

void main() {
  const String probeHost = 'xjw1.ncst.edu.cn';
  const String offHost = 'webexp.ncst.edu.cn';

  CampusNetwork classify(int status, String location) => classifyCampusProbe(
        statusCode: status,
        location: location,
        probeHost: probeHost,
        offCampusHost: offHost,
      );

  group('classifyCampusProbe', () {
    test('校外：302 跳到 webexp', () {
      expect(
        classify(302, 'https://webexp.ncst.edu.cn/login/login?x=1'),
        CampusNetwork.offCampus,
      );
    });

    test('校外：跳转到 webexp 的子域也识别', () {
      expect(
        classify(302, 'https://auth.webexp.ncst.edu.cn/login'),
        CampusNetwork.offCampus,
      );
    });

    test('校外：host 大小写 / 前后空格不影响', () {
      expect(
        classify(302, '  HTTPS://WEBEXP.NCST.EDU.CN/login  '),
        CampusNetwork.offCampus,
      );
    });

    test('校园网：302 跳到同站 http（gotoLogin）', () {
      expect(
        classify(302, 'http://xjw1.ncst.edu.cn/gotoLogin'),
        CampusNetwork.campus,
      );
    });

    test('校园网：200 直接是登录页', () {
      expect(classify(200, ''), CampusNetwork.campus);
    });

    test('校园网：相对 Location 视为同站', () {
      expect(classify(302, '/login'), CampusNetwork.campus);
    });

    test('未知：跳到不认识的 host', () {
      expect(
        classify(302, 'https://evil.example.com/login'),
        CampusNetwork.unknown,
      );
    });

    test('未知：5xx（无法判断在网内还是网外）', () {
      expect(classify(503, ''), CampusNetwork.unknown);
    });

    test('未知：3xx 但没有 Location', () {
      expect(classify(302, ''), CampusNetwork.unknown);
    });

    test('前缀伪装不算校外', () {
      expect(
        classify(302, 'https://webexp.ncst.edu.cn.evil.com/login'),
        CampusNetwork.unknown,
      );
    });
  });
}
