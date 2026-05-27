# dart_quickjs

` ⚠ 此项目的代码由AI生成 `

QuickJS-ng JavaScript 引擎的 Dart/Flutter 绑定。

使用 Dart 的 [Hooks](https://dart.dev/tools/hooks) 系统（原 native-assets）进行原生代码编译，支持所有平台：

- **Dart**: Linux, Windows, macOS
- **Flutter**: Android, iOS, Linux, Windows, macOS

## 特性

- 🚀 高性能 JavaScript 执行引擎
- 📦 自动编译原生代码，无需手动配置
- 🔄 Dart 和 JavaScript 之间的值自动转换
- ⚡ 支持 ES2023 语法
- 🧹 自动内存管理和垃圾回收
- 🔒 异常处理和错误信息

## 快速开始

### 环境要求

- Dart SDK >= 3.10.0
- C 编译器 (GCC, Clang, 或 MSVC)

### 安装

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  dart_quickjs: ^1.0.0
```

## 使用示例

### 基本用法

```dart
import 'package:dart_quickjs/dart_quickjs.dart';

void main() {
  // 创建 JavaScript 运行时
  final runtime = JsRuntime();

  try {
    // 执行简单表达式
    final result = runtime.eval('1 + 2');
    print(result); // 3

    // 执行字符串操作
    print(runtime.eval('"Hello, " + "World!"')); // Hello, World!

    // 使用 Math 对象
    print(runtime.eval('Math.sqrt(16)')); // 4.0
  } finally {
    // 释放资源
    runtime.dispose();
  }
}
```

### 调用 JavaScript 函数

```dart
final runtime = JsRuntime();

// 创建可调用的函数
final add = runtime.evalFunction('((a, b) => a + b)');

print(add.call([1, 2]));  // 3
print(add.call([10, 20])); // 30

add.dispose();
runtime.dispose();
```

### 使用全局变量

```dart
final runtime = JsRuntime();

// 设置全局变量
runtime.setGlobal('myValue', 100);
runtime.setGlobal('myArray', [1, 2, 3]);
runtime.setGlobal('myObject', {'name': 'Dart', 'version': 3});

// 在 JavaScript 中使用
print(runtime.eval('myValue * 2'));  // 200
print(runtime.eval('myArray.map(x => x * 2)'));  // [2, 4, 6]
print(runtime.eval('myObject.name'));  // Dart

// 获取全局变量
print(runtime.getGlobal('myValue'));  // 100

runtime.dispose();
```

### 处理数组和对象

```dart
final runtime = JsRuntime();

// JavaScript 数组自动转换为 Dart List
final arr = runtime.eval('[1, 2, 3, 4, 5]');
print(arr); // [1, 2, 3, 4, 5]

// JavaScript 对象自动转换为 Dart Map
final obj = runtime.eval('({name: "John", age: 30})');
print(obj); // {name: John, age: 30}

runtime.dispose();
```

### 错误处理

```dart
final runtime = JsRuntime();

try {
  runtime.eval('throw new Error("Something went wrong")');
} on JsException catch (e) {
  print('JavaScript 错误: ${e.message}');
  if (e.stack != null) {
    print('堆栈跟踪:\n${e.stack}');
  }
}

runtime.dispose();
```

## 类型转换

| JavaScript 类型 | Dart 类型 |
|----------------|-----------|
| number (整数) | int |
| number (浮点) | double |
| string | String |
| boolean | bool |
| null/undefined | null |
| Array | List |
| Object | Map<String, dynamic> |
| Function | JsFunction |
| BigInt | BigInt |

## 高级用法

### 内存限制

```dart
// 限制 JavaScript 堆内存为 32MB
final runtime = JsRuntime(memoryLimit: 32 * 1024 * 1024);
```

### 手动垃圾回收

```dart
final runtime = JsRuntime();

// 执行一些操作...

// 手动触发垃圾回收
runtime.runGC();

runtime.dispose();
```

### 执行异步任务

```dart
final runtime = JsRuntime();

// 执行包含 Promise 的代码
runtime.eval('''
  Promise.resolve().then(() => {
    globalThis.result = 42;
  });
''');

// 执行待处理的 Promise 任务
runtime.executePendingJobs();

print(runtime.getGlobal('result')); // 42

runtime.dispose();
```

## 构建原理

本包使用 Dart 3.10+ 的 [Hooks](https://dart.dev/tools/hooks) 系统自动编译 QuickJS-ng 源代码。

在运行 `dart run` 或 `flutter run` 时：
1. Dart/Flutter 工具链自动检测 `hook/build.dart`
2. 使用 `native_toolchain_c` 编译 QuickJS-ng C 代码
3. 生成平台特定的动态库
4. 自动链接到 Dart 应用程序

不需要手动编译或下载预编译库！

## 示例

### Dart 示例

```bash
cd example
dart run dart_quickjs_example.dart
```

### Flutter 示例

一个完整的 JavaScript Playground 应用，展示如何在 Flutter 中使用 QuickJS：

```bash
cd example_flutter
flutter run
```

特性：
- 交互式 JavaScript 代码编辑器
- 实时执行 JavaScript 代码
- 输出显示面板
- 重置运行时功能
- 完整的错误处理

## 许可证

MIT License

## 致谢

- [QuickJS-ng](https://github.com/nickhurst) - 现代化的 QuickJS 分支
- [dart-lang/native](https://github.com/dart-lang/native) - Dart Native 工具链

