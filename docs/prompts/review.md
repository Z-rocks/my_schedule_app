# 任务：Code Review

## 使用场景
代码写完后，提交前自查，或者让 AI review 已生成的代码。

## 模板

```text
【项目宪法】
（粘贴 docs/CONTEXT.md）

【待 Review 的代码】
（粘贴要 review 的文件完整代码）

【Review 请求】
请按照以下清单检查代码，并输出问题列表：

1. **命名规范**
   - 类名大驼峰、变量小驼峰、常量全大写下划线？
   - 私有成员有 `_` 前缀？
   - 命名是否表意清晰？

2. **空安全**
   - 是否所有可能为 null 的地方都处理了？
   - 有没有滥用 `!`？
   - `fromJson` 是否处理了 null 和类型转换？

3. **架构边界**（对照 CONTEXT.md）
   - UI 层有没有硬编码颜色/尺寸？
   - 有没有破坏"插件不接触 UI"？
   - 依赖方向是否正确（上层依赖下层，不反向）？

4. **异步与错误**
   - `async/await` 是否完整？
   - 异常是否被捕获？
   - `setState` / `notifyListeners` 前是否检查 `mounted`？

5. **性能**
   - 列表是否用 `ListView.builder`？
   - Provider 有没有不必要的 `notifyListeners`？
   - 是否有重复的 build 计算？

6. **可维护性**
   - 是否有魔法数字/字符串？
   - 长函数是否应该拆分？
   - 重复代码是否可以抽函数？

7. **文件规范**
   - 顶部是否有用途注释？
   - import 顺序：dart → package → 相对路径？
   - 有没有未使用的 import？

【输出要求】
- 按严重程度分类：🔴 必须修 / 🟡 建议修 / 🟢 可选
- 每个问题给出：文件路径、行号（如能定位）、问题描述、修复建议
- 最后给出总体评价和修复后的完整代码（如果有修改）
```

## 示例输出

```
🔴 必须修：

1. lib/models/course.dart 第 15 行
   问题：fromJson 中 `json['name'] as String` 未处理 null，
        如果 JSON 里 name 为 null 会崩溃
   修复：改为 `json['name'] as String? ?? ''`

2. lib/providers/course_provider.dart 第 45 行
   问题：notifyListeners() 在 async 方法里调用前没有检查 mounted
   修复：加 `if (!mounted) return;`

🟡 建议修：

3. lib/models/course.dart 第 8 行
   问题：字段命名 `tpl` 不清晰，建议改为 `timePlaces`

🟢 可选：

4. lib/providers/course_provider.dart
   建议：`getById` 可以用 `firstWhereOrNull` 简化
```

## 使用时机

- 每次 AI 生成代码后
- 提交 PR 前
- 重构后
- 修 bug 后