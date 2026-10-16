// Phase 8：登录成功判定的回归测试。
//
// 这个文件是**真机实测逼出来的**：学习通登录成功后 302 到
// `http://i.mooc.chaoxing.com/...`（注意是 **http**），而插件按惯例声明的
// `checkUrl` 是 `https://i.mooc.chaoxing.com/`。原来的 `startsWith` 字面匹配
// 因此永远命中不了 —— 表现是"登录明明成功了，登录页却卡住不返回"。
//
// `isLoginSuccessUrl` 是纯函数，不需要起 WebView 就能测，
// 所以把这个坑固化成用例，避免以后有人"顺手改回"字面匹配。
import 'package:flutter_test/flutter_test.dart';
import 'package:my_schedule_app/pages/login/webview_login_page.dart';

void main() {
  group('isLoginSuccessUrl：基本前缀匹配', () {
    test('URL 命中前缀 → 成功', () {
      expect(
        isLoginSuccessUrl(
          'https://i.mooc.chaoxing.com/space/index',
          'https://i.mooc.chaoxing.com/',
        ),
        isTrue,
      );
    });

    test('URL 与原前缀完全相同 → 成功', () {
      expect(
        isLoginSuccessUrl(
          'https://i.mooc.chaoxing.com/',
          'https://i.mooc.chaoxing.com/',
        ),
        isTrue,
      );
    });

    test('URL 不在前缀下 → 失败', () {
      expect(
        isLoginSuccessUrl(
          'https://passport2.chaoxing.com/login',
          'https://i.mooc.chaoxing.com/',
        ),
        isFalse,
      );
    });

    test('空前缀 → 失败（表示"不靠 URL 判定"，交给 Cookie 兜底）', () {
      expect(isLoginSuccessUrl('https://i.mooc.chaoxing.com/', ''), isFalse);
      expect(isLoginSuccessUrl('https://i.mooc.chaoxing.com/', '   '), isFalse);
    });

    test('两侧的空白会被裁掉', () {
      expect(
        isLoginSuccessUrl(
          '  https://i.mooc.chaoxing.com/space/index  ',
          '  https://i.mooc.chaoxing.com/  ',
        ),
        isTrue,
      );
    });
  });

  group('isLoginSuccessUrl：scheme 不敏感（真机实测场景）', () {
    test('前缀是 https、实际落地是 http → 仍判成功', () {
      // 这就是学习通真机上的真实情况，也是加这个特性的唯一原因。
      expect(
        isLoginSuccessUrl(
          'http://i.mooc.chaoxing.com/space/index',
          'https://i.mooc.chaoxing.com/',
        ),
        isTrue,
      );
    });

    test('前缀是 http、实际落地是 https → 也判成功（反向同样成立）', () {
      expect(
        isLoginSuccessUrl(
          'https://i.mooc.chaoxing.com/space/index',
          'http://i.mooc.chaoxing.com/',
        ),
        isTrue,
      );
    });

    test('两边都没写 scheme → 仍按前缀匹配', () {
      expect(
        isLoginSuccessUrl(
          'https://i.mooc.chaoxing.com/space/index',
          'i.mooc.chaoxing.com/',
        ),
        isTrue,
      );
    });

    test('剥掉 scheme 后主机不同 → 失败（没有放松到"任意站点都算成功"）', () {
      expect(
        isLoginSuccessUrl(
          'http://evil.com/i.mooc.chaoxing.com/space/index',
          'https://i.mooc.chaoxing.com/',
        ),
        isFalse,
      );
    });

    test('scheme 不同但路径不匹配 → 失败', () {
      expect(
        isLoginSuccessUrl(
          'http://i.mooc.chaoxing.com/other',
          'https://i.mooc.chaoxing.com/space/',
        ),
        isFalse,
      );
    });

    test('前缀只出现在 URL 中间（不在开头）→ 失败', () {
      // 防止有人把实现写成 contains / 全局 replace，那样"任何带跳转参数的
      // 第三方 URL"都会被误判成登录成功。
      expect(
        isLoginSuccessUrl(
          'https://evil.com/?next=https://i.mooc.chaoxing.com/',
          'https://i.mooc.chaoxing.com/',
        ),
        isFalse,
      );
    });
  });

  group('isLoginSuccessUrl：大小写（scheme 大小写不敏感）', () {
    test('前缀写 HTTPS:// 也能匹配 http:// 的落地页', () {
      expect(
        isLoginSuccessUrl(
          'http://i.mooc.chaoxing.com/space/index',
          'HTTPS://i.mooc.chaoxing.com/',
        ),
        isTrue,
      );
    });
  });

  group('loadErrorHint：把英文报错翻译成可照做的提示', () {
    test('明文 HTTP 被拦 → 提示指向 network_security_config（真机实测的那条）', () {
      final String? hint = loadErrorHint('net::ERR_CLEARTEXT_NOT_PERMITTED');
      expect(hint, isNotNull);
      expect(hint, contains('network_security_config.xml'));
      expect(hint, contains('明文 HTTP'));
    });

    test('DNS 解析失败 → 有对应提示', () {
      expect(loadErrorHint('net::ERR_NAME_NOT_RESOLVED'), contains('域名解析失败'));
    });

    test('连接超时 → 有对应提示', () {
      expect(loadErrorHint('net::ERR_CONNECTION_TIMED_OUT'), contains('连接超时'));
      expect(loadErrorHint('net::ERR_TIMED_OUT'), contains('连接超时'));
    });

    test('证书错误 → 有对应提示', () {
      expect(loadErrorHint('net::ERR_CERT_AUTHORITY_INVALID'), contains('证书'));
    });

    test('大小写不敏感（WebView 各平台大小写不完全一致）', () {
      expect(loadErrorHint('net::err_cleartext_not_permitted'), isNotNull);
      expect(loadErrorHint('NET::ERR_CLEARTEXT_NOT_PERMITTED'), isNotNull);
    });

    test('没见过的错误 → 返回 null（界面只显示原始报错，不编瞎话）', () {
      expect(loadErrorHint('net::ERR_SOMETHING_BRAND_NEW'), isNull);
      expect(loadErrorHint(''), isNull);
    });
  });
}
