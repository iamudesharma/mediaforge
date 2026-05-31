// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$VideoProcessorError {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoProcessorError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'VideoProcessorError()';
}


}

/// @nodoc
class $VideoProcessorErrorCopyWith<$Res>  {
$VideoProcessorErrorCopyWith(VideoProcessorError _, $Res Function(VideoProcessorError) __);
}


/// Adds pattern-matching-related methods to [VideoProcessorError].
extension VideoProcessorErrorPatterns on VideoProcessorError {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( VideoProcessorError_InvalidInput value)?  invalidInput,TResult Function( VideoProcessorError_FileNotFound value)?  fileNotFound,TResult Function( VideoProcessorError_UnsupportedCodec value)?  unsupportedCodec,TResult Function( VideoProcessorError_JobNotFound value)?  jobNotFound,TResult Function( VideoProcessorError_Cancelled value)?  cancelled,TResult Function( VideoProcessorError_IoError value)?  ioError,TResult Function( VideoProcessorError_FfmpegError value)?  ffmpegError,TResult Function( VideoProcessorError_QueueFull value)?  queueFull,TResult Function( VideoProcessorError_Internal value)?  internal,required TResult orElse(),}){
final _that = this;
switch (_that) {
case VideoProcessorError_InvalidInput() when invalidInput != null:
return invalidInput(_that);case VideoProcessorError_FileNotFound() when fileNotFound != null:
return fileNotFound(_that);case VideoProcessorError_UnsupportedCodec() when unsupportedCodec != null:
return unsupportedCodec(_that);case VideoProcessorError_JobNotFound() when jobNotFound != null:
return jobNotFound(_that);case VideoProcessorError_Cancelled() when cancelled != null:
return cancelled(_that);case VideoProcessorError_IoError() when ioError != null:
return ioError(_that);case VideoProcessorError_FfmpegError() when ffmpegError != null:
return ffmpegError(_that);case VideoProcessorError_QueueFull() when queueFull != null:
return queueFull(_that);case VideoProcessorError_Internal() when internal != null:
return internal(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( VideoProcessorError_InvalidInput value)  invalidInput,required TResult Function( VideoProcessorError_FileNotFound value)  fileNotFound,required TResult Function( VideoProcessorError_UnsupportedCodec value)  unsupportedCodec,required TResult Function( VideoProcessorError_JobNotFound value)  jobNotFound,required TResult Function( VideoProcessorError_Cancelled value)  cancelled,required TResult Function( VideoProcessorError_IoError value)  ioError,required TResult Function( VideoProcessorError_FfmpegError value)  ffmpegError,required TResult Function( VideoProcessorError_QueueFull value)  queueFull,required TResult Function( VideoProcessorError_Internal value)  internal,}){
final _that = this;
switch (_that) {
case VideoProcessorError_InvalidInput():
return invalidInput(_that);case VideoProcessorError_FileNotFound():
return fileNotFound(_that);case VideoProcessorError_UnsupportedCodec():
return unsupportedCodec(_that);case VideoProcessorError_JobNotFound():
return jobNotFound(_that);case VideoProcessorError_Cancelled():
return cancelled(_that);case VideoProcessorError_IoError():
return ioError(_that);case VideoProcessorError_FfmpegError():
return ffmpegError(_that);case VideoProcessorError_QueueFull():
return queueFull(_that);case VideoProcessorError_Internal():
return internal(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( VideoProcessorError_InvalidInput value)?  invalidInput,TResult? Function( VideoProcessorError_FileNotFound value)?  fileNotFound,TResult? Function( VideoProcessorError_UnsupportedCodec value)?  unsupportedCodec,TResult? Function( VideoProcessorError_JobNotFound value)?  jobNotFound,TResult? Function( VideoProcessorError_Cancelled value)?  cancelled,TResult? Function( VideoProcessorError_IoError value)?  ioError,TResult? Function( VideoProcessorError_FfmpegError value)?  ffmpegError,TResult? Function( VideoProcessorError_QueueFull value)?  queueFull,TResult? Function( VideoProcessorError_Internal value)?  internal,}){
final _that = this;
switch (_that) {
case VideoProcessorError_InvalidInput() when invalidInput != null:
return invalidInput(_that);case VideoProcessorError_FileNotFound() when fileNotFound != null:
return fileNotFound(_that);case VideoProcessorError_UnsupportedCodec() when unsupportedCodec != null:
return unsupportedCodec(_that);case VideoProcessorError_JobNotFound() when jobNotFound != null:
return jobNotFound(_that);case VideoProcessorError_Cancelled() when cancelled != null:
return cancelled(_that);case VideoProcessorError_IoError() when ioError != null:
return ioError(_that);case VideoProcessorError_FfmpegError() when ffmpegError != null:
return ffmpegError(_that);case VideoProcessorError_QueueFull() when queueFull != null:
return queueFull(_that);case VideoProcessorError_Internal() when internal != null:
return internal(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String field0)?  invalidInput,TResult Function( String field0)?  fileNotFound,TResult Function( String field0)?  unsupportedCodec,TResult Function( String field0)?  jobNotFound,TResult Function()?  cancelled,TResult Function( String field0)?  ioError,TResult Function( String field0)?  ffmpegError,TResult Function()?  queueFull,TResult Function( String field0)?  internal,required TResult orElse(),}) {final _that = this;
switch (_that) {
case VideoProcessorError_InvalidInput() when invalidInput != null:
return invalidInput(_that.field0);case VideoProcessorError_FileNotFound() when fileNotFound != null:
return fileNotFound(_that.field0);case VideoProcessorError_UnsupportedCodec() when unsupportedCodec != null:
return unsupportedCodec(_that.field0);case VideoProcessorError_JobNotFound() when jobNotFound != null:
return jobNotFound(_that.field0);case VideoProcessorError_Cancelled() when cancelled != null:
return cancelled();case VideoProcessorError_IoError() when ioError != null:
return ioError(_that.field0);case VideoProcessorError_FfmpegError() when ffmpegError != null:
return ffmpegError(_that.field0);case VideoProcessorError_QueueFull() when queueFull != null:
return queueFull();case VideoProcessorError_Internal() when internal != null:
return internal(_that.field0);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String field0)  invalidInput,required TResult Function( String field0)  fileNotFound,required TResult Function( String field0)  unsupportedCodec,required TResult Function( String field0)  jobNotFound,required TResult Function()  cancelled,required TResult Function( String field0)  ioError,required TResult Function( String field0)  ffmpegError,required TResult Function()  queueFull,required TResult Function( String field0)  internal,}) {final _that = this;
switch (_that) {
case VideoProcessorError_InvalidInput():
return invalidInput(_that.field0);case VideoProcessorError_FileNotFound():
return fileNotFound(_that.field0);case VideoProcessorError_UnsupportedCodec():
return unsupportedCodec(_that.field0);case VideoProcessorError_JobNotFound():
return jobNotFound(_that.field0);case VideoProcessorError_Cancelled():
return cancelled();case VideoProcessorError_IoError():
return ioError(_that.field0);case VideoProcessorError_FfmpegError():
return ffmpegError(_that.field0);case VideoProcessorError_QueueFull():
return queueFull();case VideoProcessorError_Internal():
return internal(_that.field0);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String field0)?  invalidInput,TResult? Function( String field0)?  fileNotFound,TResult? Function( String field0)?  unsupportedCodec,TResult? Function( String field0)?  jobNotFound,TResult? Function()?  cancelled,TResult? Function( String field0)?  ioError,TResult? Function( String field0)?  ffmpegError,TResult? Function()?  queueFull,TResult? Function( String field0)?  internal,}) {final _that = this;
switch (_that) {
case VideoProcessorError_InvalidInput() when invalidInput != null:
return invalidInput(_that.field0);case VideoProcessorError_FileNotFound() when fileNotFound != null:
return fileNotFound(_that.field0);case VideoProcessorError_UnsupportedCodec() when unsupportedCodec != null:
return unsupportedCodec(_that.field0);case VideoProcessorError_JobNotFound() when jobNotFound != null:
return jobNotFound(_that.field0);case VideoProcessorError_Cancelled() when cancelled != null:
return cancelled();case VideoProcessorError_IoError() when ioError != null:
return ioError(_that.field0);case VideoProcessorError_FfmpegError() when ffmpegError != null:
return ffmpegError(_that.field0);case VideoProcessorError_QueueFull() when queueFull != null:
return queueFull();case VideoProcessorError_Internal() when internal != null:
return internal(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class VideoProcessorError_InvalidInput extends VideoProcessorError {
  const VideoProcessorError_InvalidInput(this.field0): super._();
  

 final  String field0;

/// Create a copy of VideoProcessorError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoProcessorError_InvalidInputCopyWith<VideoProcessorError_InvalidInput> get copyWith => _$VideoProcessorError_InvalidInputCopyWithImpl<VideoProcessorError_InvalidInput>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoProcessorError_InvalidInput&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VideoProcessorError.invalidInput(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VideoProcessorError_InvalidInputCopyWith<$Res> implements $VideoProcessorErrorCopyWith<$Res> {
  factory $VideoProcessorError_InvalidInputCopyWith(VideoProcessorError_InvalidInput value, $Res Function(VideoProcessorError_InvalidInput) _then) = _$VideoProcessorError_InvalidInputCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$VideoProcessorError_InvalidInputCopyWithImpl<$Res>
    implements $VideoProcessorError_InvalidInputCopyWith<$Res> {
  _$VideoProcessorError_InvalidInputCopyWithImpl(this._self, this._then);

  final VideoProcessorError_InvalidInput _self;
  final $Res Function(VideoProcessorError_InvalidInput) _then;

/// Create a copy of VideoProcessorError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VideoProcessorError_InvalidInput(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class VideoProcessorError_FileNotFound extends VideoProcessorError {
  const VideoProcessorError_FileNotFound(this.field0): super._();
  

 final  String field0;

/// Create a copy of VideoProcessorError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoProcessorError_FileNotFoundCopyWith<VideoProcessorError_FileNotFound> get copyWith => _$VideoProcessorError_FileNotFoundCopyWithImpl<VideoProcessorError_FileNotFound>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoProcessorError_FileNotFound&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VideoProcessorError.fileNotFound(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VideoProcessorError_FileNotFoundCopyWith<$Res> implements $VideoProcessorErrorCopyWith<$Res> {
  factory $VideoProcessorError_FileNotFoundCopyWith(VideoProcessorError_FileNotFound value, $Res Function(VideoProcessorError_FileNotFound) _then) = _$VideoProcessorError_FileNotFoundCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$VideoProcessorError_FileNotFoundCopyWithImpl<$Res>
    implements $VideoProcessorError_FileNotFoundCopyWith<$Res> {
  _$VideoProcessorError_FileNotFoundCopyWithImpl(this._self, this._then);

  final VideoProcessorError_FileNotFound _self;
  final $Res Function(VideoProcessorError_FileNotFound) _then;

/// Create a copy of VideoProcessorError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VideoProcessorError_FileNotFound(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class VideoProcessorError_UnsupportedCodec extends VideoProcessorError {
  const VideoProcessorError_UnsupportedCodec(this.field0): super._();
  

 final  String field0;

/// Create a copy of VideoProcessorError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoProcessorError_UnsupportedCodecCopyWith<VideoProcessorError_UnsupportedCodec> get copyWith => _$VideoProcessorError_UnsupportedCodecCopyWithImpl<VideoProcessorError_UnsupportedCodec>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoProcessorError_UnsupportedCodec&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VideoProcessorError.unsupportedCodec(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VideoProcessorError_UnsupportedCodecCopyWith<$Res> implements $VideoProcessorErrorCopyWith<$Res> {
  factory $VideoProcessorError_UnsupportedCodecCopyWith(VideoProcessorError_UnsupportedCodec value, $Res Function(VideoProcessorError_UnsupportedCodec) _then) = _$VideoProcessorError_UnsupportedCodecCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$VideoProcessorError_UnsupportedCodecCopyWithImpl<$Res>
    implements $VideoProcessorError_UnsupportedCodecCopyWith<$Res> {
  _$VideoProcessorError_UnsupportedCodecCopyWithImpl(this._self, this._then);

  final VideoProcessorError_UnsupportedCodec _self;
  final $Res Function(VideoProcessorError_UnsupportedCodec) _then;

/// Create a copy of VideoProcessorError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VideoProcessorError_UnsupportedCodec(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class VideoProcessorError_JobNotFound extends VideoProcessorError {
  const VideoProcessorError_JobNotFound(this.field0): super._();
  

 final  String field0;

/// Create a copy of VideoProcessorError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoProcessorError_JobNotFoundCopyWith<VideoProcessorError_JobNotFound> get copyWith => _$VideoProcessorError_JobNotFoundCopyWithImpl<VideoProcessorError_JobNotFound>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoProcessorError_JobNotFound&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VideoProcessorError.jobNotFound(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VideoProcessorError_JobNotFoundCopyWith<$Res> implements $VideoProcessorErrorCopyWith<$Res> {
  factory $VideoProcessorError_JobNotFoundCopyWith(VideoProcessorError_JobNotFound value, $Res Function(VideoProcessorError_JobNotFound) _then) = _$VideoProcessorError_JobNotFoundCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$VideoProcessorError_JobNotFoundCopyWithImpl<$Res>
    implements $VideoProcessorError_JobNotFoundCopyWith<$Res> {
  _$VideoProcessorError_JobNotFoundCopyWithImpl(this._self, this._then);

  final VideoProcessorError_JobNotFound _self;
  final $Res Function(VideoProcessorError_JobNotFound) _then;

/// Create a copy of VideoProcessorError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VideoProcessorError_JobNotFound(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class VideoProcessorError_Cancelled extends VideoProcessorError {
  const VideoProcessorError_Cancelled(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoProcessorError_Cancelled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'VideoProcessorError.cancelled()';
}


}




/// @nodoc


class VideoProcessorError_IoError extends VideoProcessorError {
  const VideoProcessorError_IoError(this.field0): super._();
  

 final  String field0;

/// Create a copy of VideoProcessorError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoProcessorError_IoErrorCopyWith<VideoProcessorError_IoError> get copyWith => _$VideoProcessorError_IoErrorCopyWithImpl<VideoProcessorError_IoError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoProcessorError_IoError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VideoProcessorError.ioError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VideoProcessorError_IoErrorCopyWith<$Res> implements $VideoProcessorErrorCopyWith<$Res> {
  factory $VideoProcessorError_IoErrorCopyWith(VideoProcessorError_IoError value, $Res Function(VideoProcessorError_IoError) _then) = _$VideoProcessorError_IoErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$VideoProcessorError_IoErrorCopyWithImpl<$Res>
    implements $VideoProcessorError_IoErrorCopyWith<$Res> {
  _$VideoProcessorError_IoErrorCopyWithImpl(this._self, this._then);

  final VideoProcessorError_IoError _self;
  final $Res Function(VideoProcessorError_IoError) _then;

/// Create a copy of VideoProcessorError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VideoProcessorError_IoError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class VideoProcessorError_FfmpegError extends VideoProcessorError {
  const VideoProcessorError_FfmpegError(this.field0): super._();
  

 final  String field0;

/// Create a copy of VideoProcessorError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoProcessorError_FfmpegErrorCopyWith<VideoProcessorError_FfmpegError> get copyWith => _$VideoProcessorError_FfmpegErrorCopyWithImpl<VideoProcessorError_FfmpegError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoProcessorError_FfmpegError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VideoProcessorError.ffmpegError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VideoProcessorError_FfmpegErrorCopyWith<$Res> implements $VideoProcessorErrorCopyWith<$Res> {
  factory $VideoProcessorError_FfmpegErrorCopyWith(VideoProcessorError_FfmpegError value, $Res Function(VideoProcessorError_FfmpegError) _then) = _$VideoProcessorError_FfmpegErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$VideoProcessorError_FfmpegErrorCopyWithImpl<$Res>
    implements $VideoProcessorError_FfmpegErrorCopyWith<$Res> {
  _$VideoProcessorError_FfmpegErrorCopyWithImpl(this._self, this._then);

  final VideoProcessorError_FfmpegError _self;
  final $Res Function(VideoProcessorError_FfmpegError) _then;

/// Create a copy of VideoProcessorError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VideoProcessorError_FfmpegError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class VideoProcessorError_QueueFull extends VideoProcessorError {
  const VideoProcessorError_QueueFull(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoProcessorError_QueueFull);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'VideoProcessorError.queueFull()';
}


}




/// @nodoc


class VideoProcessorError_Internal extends VideoProcessorError {
  const VideoProcessorError_Internal(this.field0): super._();
  

 final  String field0;

/// Create a copy of VideoProcessorError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VideoProcessorError_InternalCopyWith<VideoProcessorError_Internal> get copyWith => _$VideoProcessorError_InternalCopyWithImpl<VideoProcessorError_Internal>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoProcessorError_Internal&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VideoProcessorError.internal(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VideoProcessorError_InternalCopyWith<$Res> implements $VideoProcessorErrorCopyWith<$Res> {
  factory $VideoProcessorError_InternalCopyWith(VideoProcessorError_Internal value, $Res Function(VideoProcessorError_Internal) _then) = _$VideoProcessorError_InternalCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$VideoProcessorError_InternalCopyWithImpl<$Res>
    implements $VideoProcessorError_InternalCopyWith<$Res> {
  _$VideoProcessorError_InternalCopyWithImpl(this._self, this._then);

  final VideoProcessorError_Internal _self;
  final $Res Function(VideoProcessorError_Internal) _then;

/// Create a copy of VideoProcessorError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VideoProcessorError_Internal(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
