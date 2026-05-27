import 'package:dart_quickjs/dart_quickjs.dart';

void main() {
  // Create a new JavaScript runtime
  final runtime = JsRuntime();

  try {
    // Basic expressions
    print('=== Basic Expressions ===');
    print('1 + 2 = ${runtime.eval('1 + 2')}');
    print('10 * 5 = ${runtime.eval('10 * 5')}');
    print('Math.sqrt(16) = ${runtime.eval('Math.sqrt(16)')}');

    // Strings
    print('\n=== Strings ===');
    print(runtime.eval('"Hello, " + "World!"'));
    print('Length: ${runtime.eval('"Hello".length')}');

    // Arrays
    print('\n=== Arrays ===');
    final arr = runtime.eval('[1, 2, 3, 4, 5]');
    print('Array: $arr');
    print('Map: ${runtime.eval('[1,2,3].map(x => x * 2)')}');

    // Objects
    print('\n=== Objects ===');
    final obj = runtime.eval('({name: "John", age: 30, city: "New York"})');
    print('Object: $obj');

    // Functions
    print('\n=== Functions ===');
    final add = runtime.evalFunction('((a, b) => a + b)');
    print('add(3, 4) = ${add.call([3, 4])}');
    print('add(10, 20) = ${add.call([10, 20])}');
    add.dispose();

    // Using global variables
    print('\n=== Global Variables ===');
    runtime.setGlobal('myValue', 100);
    runtime.setGlobal('myName', 'Dart');
    print('myValue * 2 = ${runtime.eval('myValue * 2')}');
    print('Hello from ${runtime.eval('"Hello from " + myName')}');

    // Complex JavaScript code
    print('\n=== Complex JavaScript ===');
    final fibonacci = runtime.evalFunction('''
      (function(n) {
        if (n <= 1) return n;
        let a = 0, b = 1;
        for (let i = 2; i <= n; i++) {
          let temp = a + b;
          a = b;
          b = temp;
        }
        return b;
      })
    ''');
    print('Fibonacci(10) = ${fibonacci.call([10])}');
    print('Fibonacci(20) = ${fibonacci.call([20])}');
    fibonacci.dispose();

    // JSON operations
    print('\n=== JSON Operations ===');
    runtime.setGlobal('data', {
      'users': ['Alice', 'Bob', 'Charlie'],
      'count': 3,
    });
    print('Users: ${runtime.eval('data.users')}');
    print('Count: ${runtime.eval('data.count')}');

    // Async tasks (Promise)
    print('\n=== Async Tasks (Promise) ===');
    runtime.eval('''
      globalThis.asyncResult = null;
      globalThis.asyncStatus = "pending";
      
      Promise.resolve(42)
        .then(value => {
          globalThis.asyncResult = value * 2;
          globalThis.asyncStatus = "fulfilled";
          return globalThis.asyncResult;
        })
        .then(value => {
          globalThis.asyncResult = "Final: " + value;
        });
    ''');
    print(
      'Before executePendingJobs: status = ${runtime.getGlobal('asyncStatus')}',
    );
    runtime.executePendingJobs();
    print(
      'After executePendingJobs: status = ${runtime.getGlobal('asyncStatus')}',
    );
    print('Async result: ${runtime.getGlobal('asyncResult')}');

    // More complex async example with setTimeout simulation
    print('\n=== Promise Chain ===');
    runtime.eval('''
      globalThis.steps = [];
      
      new Promise((resolve) => {
        steps.push("Step 1: Promise created");
        resolve(10);
      })
      .then(value => {
        steps.push("Step 2: Got " + value);
        return value * 2;
      })
      .then(value => {
        steps.push("Step 3: Got " + value);
        return value + 5;
      })
      .then(value => {
        steps.push("Step 4: Final value = " + value);
      });
    ''');
    runtime.executePendingJobs();
    final steps = runtime.getGlobal('steps') as List;
    for (final step in steps) {
      print('  $step');
    }

    // Error handling
    print('\n=== Error Handling ===');
    try {
      runtime.eval('throw new Error("This is a test error")');
    } on JsException catch (e) {
      print('Caught JavaScript error: ${e.message}');
    }

    // Garbage collection
    print('\n=== Garbage Collection ===');
    runtime.runGC();
    print('GC completed');
  } finally {
    // Always dispose the runtime when done
    runtime.dispose();
    print('\n=== Runtime disposed ===');
  }
}
