// 登录页"登录后自动跳转"的判定逻辑测试（P1-7 回归护栏）。
//
// 起因：NCST 插件登录成功后停在教务首页，而成功判定前缀指向"选课结果"，
// 用户必须自己点菜单，登录页才会返回。修法是插件声明 postLoginUrl，
// 内核在"已离开登录表单页"时自动导航过去。
//
// 这里只测纯函数——真实的 WebView 导航无法在 flutter test 里跑。
import 'package:flutter_test/flutter_test.dart';
import 'package:my_schedule_app/pages/login/webview_login_page.dart';

const String _loginUrl = 'https://xjw1.ncst.edu.cn/';
const String _checkUrl =
    'https://xjw1.ncst.edu.cn/student/courseSelect/courseSelectResult/index';

void main() {
  group('isLoginFormUrl', () {
    test('停在登录入口本身 → 是表单页', () {
      expect(
        isLoginFormUrl(currentUrl: _loginUrl, loginUrl: _loginUrl),
        isTrue,
      );
    });

    test('末尾斜杠差异不算离开表单页', () {
      expect(
        isLoginFormUrl(
          currentUrl: 'https://xjw1.ncst.edu.cn',
          loginUrl: _loginUrl,
        ),
        isTrue,
      );
    });

    test('登录后跳到站内深层页面 → 不是表单页（这是自动跳转的触发点）', () {
      expect(
        isLoginFormUrl(
          currentUrl: 'https://xjw1.ncst.edu.cn/student/index',
          loginUrl: _loginUrl,
        ),
        isFalse,
      );
    });

    test('路径含 login / cas 关键词 → 判为表单页', () {
      expect(
        isLoginFormUrl(
          currentUrl: 'https://xjw1.ncst.edu.cn/login?redirect=1',
          loginUrl: _loginUrl,
        ),
        isTrue,
      );
      expect(
        isLoginFormUrl(
          currentUrl: 'https://xjw1.ncst.edu.cn/cas/login',
          loginUrl: _loginUrl,
        ),
        isTrue,
      );
    });

    test('别的站点同路径 → 不是本插件的表单页', () {
      expect(
        isLoginFormUrl(
          currentUrl: 'https://evil.com/',
          loginUrl: _loginUrl,
        ),
        isFalse,
      );
    });
  });

  group('shouldAutoNavigateAfterLogin', () {
    bool check({
      required String currentUrl,
      String postLoginUrl = _checkUrl,
      bool alreadyNavigated = false,
      String successUrlPrefix = _checkUrl,
    }) {
      return shouldAutoNavigateAfterLogin(
        currentUrl: currentUrl,
        loginUrl: _loginUrl,
        successUrlPrefix: successUrlPrefix,
        postLoginUrl: postLoginUrl,
        alreadyNavigated: alreadyNavigated,
      );
    }

    test('插件未声明 postLoginUrl → 永不自动跳转（老插件行为不变）', () {
      expect(
        check(
          currentUrl: 'https://xjw1.ncst.edu.cn/student/index',
          postLoginUrl: '',
        ),
        isFalse,
      );
    });

    test('登录后停在站内首页 → 自动跳转到选课结果', () {
      expect(
        check(currentUrl: 'https://xjw1.ncst.edu.cn/student/index'),
        isTrue,
      );
    });

    test('还停在登录表单页 → 不跳（否则会打断用户输入）', () {
      expect(check(currentUrl: _loginUrl), isFalse);
      expect(
        check(currentUrl: 'https://xjw1.ncst.edu.cn/login'),
        isFalse,
      );
    });

    test('已经命中成功前缀 → 不跳（已经到了）', () {
      expect(check(currentUrl: _checkUrl), isFalse);
    });

    test('本轮已自动跳转过 → 不重复跳（防止来回弹）', () {
      expect(
        check(
          currentUrl: 'https://xjw1.ncst.edu.cn/student/index',
          alreadyNavigated: true,
        ),
        isFalse,
      );
    });

    test('跨域页面 → 不介入（CAS 单点登录链路不被打断）', () {
      expect(
        check(currentUrl: 'https://cas.ncst.edu.cn/auth?ticket=1'),
        isFalse,
      );
    });
  });
}
