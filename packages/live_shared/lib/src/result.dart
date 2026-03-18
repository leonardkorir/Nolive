class Result<T> {
  const Result.success(this.value)
      : error = null,
        isSuccess = true;

  const Result.failure(this.error)
      : value = null,
        isSuccess = false;

  final T? value;
  final Object? error;
  final bool isSuccess;
}
