import 'package:flutter/material.dart';
import 'package:dart_quickjs/dart_quickjs.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickJS Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const JavaScriptPlayground(),
    );
  }
}

class JavaScriptPlayground extends StatefulWidget {
  const JavaScriptPlayground({super.key});

  @override
  State<JavaScriptPlayground> createState() => _JavaScriptPlaygroundState();
}

class _JavaScriptPlaygroundState extends State<JavaScriptPlayground> {
  late JsRuntime _runtime;
  final _codeController = TextEditingController();
  String _output = '';
  bool _isLoading = false;
  final List<ExecutionResult> _history = [];

  @override
  void initState() {
    super.initState();
    _runtime = JsRuntime(memoryLimit: 4 * 1024 * 1024, maxStackSize: 64 * 1024);
    _codeController.text = '// 输入 JavaScript 代码\n1 + 2 * 3';
  }

  @override
  void dispose() {
    _runtime.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _executeCode() {
    setState(() {
      _isLoading = true;
    });

    final code = _codeController.text;
    String result;
    bool isError = false;

    try {
      final value = _runtime.eval(code);
      result = _formatResult(value);
    } on JsException catch (e) {
      result = '❌ Error: ${e.message}';
      if (e.stack != null) {
        result += '\n\nStack:\n${e.stack}';
      }
      isError = true;
    } catch (e) {
      result = '❌ Dart Error: $e';
      isError = true;
    }

    setState(() {
      _output = result;
      _isLoading = false;
      _history.insert(
        0,
        ExecutionResult(
          code: code,
          result: result,
          isError: isError,
          timestamp: DateTime.now(),
        ),
      );
    });
  }

  String _formatResult(dynamic value) {
    if (value == null) {
      return 'undefined';
    } else if (value is String) {
      return '"$value"';
    } else if (value is List) {
      return '[${value.map(_formatResult).join(', ')}]';
    } else if (value is Map) {
      final entries = value.entries
          .map((e) => '${e.key}: ${_formatResult(e.value)}')
          .join(', ');
      return '{$entries}';
    } else if (value is JsFunction) {
      return '[Function]';
    } else {
      return value.toString();
    }
  }

  void _runExample(String code) {
    _codeController.text = code;
    _executeCode();
  }

  void _clearHistory() {
    setState(() {
      _history.clear();
      _output = '';
    });
  }

  void _resetRuntime() {
    _runtime.dispose();
    _runtime = JsRuntime(memoryLimit: 4 * 1024 * 1024, maxStackSize: 64 * 1024);
    setState(() {
      _output = '✅ Runtime 已重置';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('QuickJS Playground'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重置 Runtime',
            onPressed: _resetRuntime,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空历史',
            onPressed: _clearHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          // 示例按钮
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                _ExampleChip(
                  label: '算术',
                  onTap: () => _runExample('1 + 2 * 3 - 4 / 2'),
                ),
                _ExampleChip(
                  label: '字符串',
                  onTap: () => _runExample('"Hello, " + "Flutter!"'),
                ),
                _ExampleChip(
                  label: '数组',
                  onTap: () => _runExample('[1, 2, 3, 4, 5].map(x => x * 2)'),
                ),
                _ExampleChip(
                  label: '对象',
                  onTap: () => _runExample(
                    '({name: "QuickJS", version: 2024, features: ["ES2023", "BigInt", "Promise"]})',
                  ),
                ),
                _ExampleChip(
                  label: 'Math',
                  onTap: () => _runExample('Math.sqrt(2) + Math.PI'),
                ),
                _ExampleChip(
                  label: 'Fibonacci',
                  onTap: () => _runExample('''
(function fib(n) {
  if (n <= 1) return n;
  let a = 0, b = 1;
  for (let i = 2; i <= n; i++) {
    [a, b] = [b, a + b];
  }
  return b;
})(20)'''),
                ),
                _ExampleChip(
                  label: 'JSON',
                  onTap: () => _runExample(
                    'JSON.stringify({hello: "world", number: 42}, null, 2)',
                  ),
                ),
                _ExampleChip(
                  label: 'Promise',
                  onTap: () => _runExample('''
// Promise 异步示例
globalThis.result = "pending";

Promise.resolve(42)
  .then(v => v * 2)
  .then(v => {
    globalThis.result = "Result: " + v;
    return v;
  });

// 执行待处理的异步任务
std.evalScript("void 0"); // trigger job execution
globalThis.result'''),
                ),
                _ExampleChip(
                  label: 'Async Chain',
                  onTap: () => _runExample('''
// Promise 链式调用
let steps = [];

new Promise(resolve => {
  steps.push("1. Created");
  resolve(10);
})
.then(v => { steps.push("2. Got " + v); return v * 2; })
.then(v => { steps.push("3. Got " + v); return v + 5; })
.then(v => { steps.push("4. Final: " + v); });

std.evalScript("void 0");
steps'''),
                ),
                _ExampleChip(
                  label: 'Error',
                  onTap: () =>
                      _runExample('throw new Error("Test error message")'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 代码输入区
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _codeController,
                maxLines: null,
                expands: true,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                decoration: InputDecoration(
                  hintText: '输入 JavaScript 代码...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                ),
              ),
            ),
          ),

          // 执行按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _executeCode,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_isLoading ? '执行中...' : '执行代码'),
              ),
            ),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),

          // 输出区
          Expanded(
            flex: 3,
            child: _output.isEmpty && _history.isEmpty
                ? const Center(
                    child: Text(
                      '点击"执行代码"运行 JavaScript',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      if (_output.isNotEmpty) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      _output.startsWith('❌')
                                          ? Icons.error
                                          : Icons.check_circle,
                                      color: _output.startsWith('❌')
                                          ? Colors.red
                                          : Colors.green,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      '结果',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  _output,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                    color: _output.startsWith('❌')
                                        ? Colors.red.shade700
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_history.isNotEmpty) ...[
                        Text(
                          '执行历史',
                          style: Theme.of(
                            context,
                          ).textTheme.titleSmall?.copyWith(color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        ..._history
                            .skip(1)
                            .take(10)
                            .map(
                              (item) => _HistoryItem(
                                result: item,
                                onTap: () {
                                  _codeController.text = item.code;
                                },
                              ),
                            ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class ExecutionResult {
  final String code;
  final String result;
  final bool isError;
  final DateTime timestamp;

  ExecutionResult({
    required this.code,
    required this.result,
    required this.isError,
    required this.timestamp,
  });
}

class _ExampleChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ExampleChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(label: Text(label), onPressed: onTap),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  final ExecutionResult result;
  final VoidCallback onTap;

  const _HistoryItem({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final code = result.code.length > 50
        ? '${result.code.substring(0, 50)}...'
        : result.code;
    final output = result.result.length > 30
        ? '${result.result.substring(0, 30)}...'
        : result.result;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                result.isError ? Icons.error_outline : Icons.code,
                size: 20,
                color: result.isError ? Colors.red : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      code.replaceAll('\n', ' '),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '→ $output',
                      style: TextStyle(
                        fontSize: 12,
                        color: result.isError
                            ? Colors.red
                            : Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                _formatTime(result.timestamp),
                style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}
