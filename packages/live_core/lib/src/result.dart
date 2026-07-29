class Result<T> {
  const Result.success(this.value) : error = null, isSuccess = true;

  const Result.failure(this.error) : value = null, isSuccess = false;

  final T? value;
  final Object? error;
  final bool isSuccess;

  bool get isFailure => !isSuccess;

  R when<R>({
    required R Function(T? value) success,
    required R Function(Object? error) failure,
  }) {
    if (isSuccess) {
      return success(value);
    }
    return failure(error);
  }

  Result<R> map<R>(R Function(T? value) transform) {
    if (isSuccess) {
      return Result<R>.success(transform(value));
    }
    return Result<R>.failure(error);
  }

  R fold<R>(R Function(T? value) success, R Function(Object? error) failure) {
    return when(success: success, failure: failure);
  }
}
