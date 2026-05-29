// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$JobResult {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'JobResult()';
}


}

/// @nodoc
class $JobResultCopyWith<$Res>  {
$JobResultCopyWith(JobResult _, $Res Function(JobResult) __);
}


/// Adds pattern-matching-related methods to [JobResult].
extension JobResultPatterns on JobResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( JobResult_Compress value)?  compress,TResult Function( JobResult_Empty value)?  empty,required TResult orElse(),}){
final _that = this;
switch (_that) {
case JobResult_Compress() when compress != null:
return compress(_that);case JobResult_Empty() when empty != null:
return empty(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( JobResult_Compress value)  compress,required TResult Function( JobResult_Empty value)  empty,}){
final _that = this;
switch (_that) {
case JobResult_Compress():
return compress(_that);case JobResult_Empty():
return empty(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( JobResult_Compress value)?  compress,TResult? Function( JobResult_Empty value)?  empty,}){
final _that = this;
switch (_that) {
case JobResult_Compress() when compress != null:
return compress(_that);case JobResult_Empty() when empty != null:
return empty(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( CompressResult field0)?  compress,TResult Function()?  empty,required TResult orElse(),}) {final _that = this;
switch (_that) {
case JobResult_Compress() when compress != null:
return compress(_that.field0);case JobResult_Empty() when empty != null:
return empty();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( CompressResult field0)  compress,required TResult Function()  empty,}) {final _that = this;
switch (_that) {
case JobResult_Compress():
return compress(_that.field0);case JobResult_Empty():
return empty();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( CompressResult field0)?  compress,TResult? Function()?  empty,}) {final _that = this;
switch (_that) {
case JobResult_Compress() when compress != null:
return compress(_that.field0);case JobResult_Empty() when empty != null:
return empty();case _:
  return null;

}
}

}

/// @nodoc


class JobResult_Compress extends JobResult {
  const JobResult_Compress(this.field0): super._();
  

 final  CompressResult field0;

/// Create a copy of JobResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JobResult_CompressCopyWith<JobResult_Compress> get copyWith => _$JobResult_CompressCopyWithImpl<JobResult_Compress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobResult_Compress&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'JobResult.compress(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $JobResult_CompressCopyWith<$Res> implements $JobResultCopyWith<$Res> {
  factory $JobResult_CompressCopyWith(JobResult_Compress value, $Res Function(JobResult_Compress) _then) = _$JobResult_CompressCopyWithImpl;
@useResult
$Res call({
 CompressResult field0
});




}
/// @nodoc
class _$JobResult_CompressCopyWithImpl<$Res>
    implements $JobResult_CompressCopyWith<$Res> {
  _$JobResult_CompressCopyWithImpl(this._self, this._then);

  final JobResult_Compress _self;
  final $Res Function(JobResult_Compress) _then;

/// Create a copy of JobResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(JobResult_Compress(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as CompressResult,
  ));
}


}

/// @nodoc


class JobResult_Empty extends JobResult {
  const JobResult_Empty(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobResult_Empty);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'JobResult.empty()';
}


}




/// @nodoc
mixin _$PlaybackFrame {

 Object get field0;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlaybackFrame&&const DeepCollectionEquality().equals(other.field0, field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(field0));

@override
String toString() {
  return 'PlaybackFrame(field0: $field0)';
}


}

/// @nodoc
class $PlaybackFrameCopyWith<$Res>  {
$PlaybackFrameCopyWith(PlaybackFrame _, $Res Function(PlaybackFrame) __);
}


/// Adds pattern-matching-related methods to [PlaybackFrame].
extension PlaybackFramePatterns on PlaybackFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PlaybackFrame_Rgba value)?  rgba,TResult Function( PlaybackFrame_PixelBuffer value)?  pixelBuffer,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PlaybackFrame_Rgba() when rgba != null:
return rgba(_that);case PlaybackFrame_PixelBuffer() when pixelBuffer != null:
return pixelBuffer(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PlaybackFrame_Rgba value)  rgba,required TResult Function( PlaybackFrame_PixelBuffer value)  pixelBuffer,}){
final _that = this;
switch (_that) {
case PlaybackFrame_Rgba():
return rgba(_that);case PlaybackFrame_PixelBuffer():
return pixelBuffer(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PlaybackFrame_Rgba value)?  rgba,TResult? Function( PlaybackFrame_PixelBuffer value)?  pixelBuffer,}){
final _that = this;
switch (_that) {
case PlaybackFrame_Rgba() when rgba != null:
return rgba(_that);case PlaybackFrame_PixelBuffer() when pixelBuffer != null:
return pixelBuffer(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( PreviewFrameRgba field0)?  rgba,TResult Function( PreviewFramePixelBuffer field0)?  pixelBuffer,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PlaybackFrame_Rgba() when rgba != null:
return rgba(_that.field0);case PlaybackFrame_PixelBuffer() when pixelBuffer != null:
return pixelBuffer(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( PreviewFrameRgba field0)  rgba,required TResult Function( PreviewFramePixelBuffer field0)  pixelBuffer,}) {final _that = this;
switch (_that) {
case PlaybackFrame_Rgba():
return rgba(_that.field0);case PlaybackFrame_PixelBuffer():
return pixelBuffer(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( PreviewFrameRgba field0)?  rgba,TResult? Function( PreviewFramePixelBuffer field0)?  pixelBuffer,}) {final _that = this;
switch (_that) {
case PlaybackFrame_Rgba() when rgba != null:
return rgba(_that.field0);case PlaybackFrame_PixelBuffer() when pixelBuffer != null:
return pixelBuffer(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class PlaybackFrame_Rgba extends PlaybackFrame {
  const PlaybackFrame_Rgba(this.field0): super._();
  

@override final  PreviewFrameRgba field0;

/// Create a copy of PlaybackFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlaybackFrame_RgbaCopyWith<PlaybackFrame_Rgba> get copyWith => _$PlaybackFrame_RgbaCopyWithImpl<PlaybackFrame_Rgba>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlaybackFrame_Rgba&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'PlaybackFrame.rgba(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $PlaybackFrame_RgbaCopyWith<$Res> implements $PlaybackFrameCopyWith<$Res> {
  factory $PlaybackFrame_RgbaCopyWith(PlaybackFrame_Rgba value, $Res Function(PlaybackFrame_Rgba) _then) = _$PlaybackFrame_RgbaCopyWithImpl;
@useResult
$Res call({
 PreviewFrameRgba field0
});




}
/// @nodoc
class _$PlaybackFrame_RgbaCopyWithImpl<$Res>
    implements $PlaybackFrame_RgbaCopyWith<$Res> {
  _$PlaybackFrame_RgbaCopyWithImpl(this._self, this._then);

  final PlaybackFrame_Rgba _self;
  final $Res Function(PlaybackFrame_Rgba) _then;

/// Create a copy of PlaybackFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(PlaybackFrame_Rgba(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as PreviewFrameRgba,
  ));
}


}

/// @nodoc


class PlaybackFrame_PixelBuffer extends PlaybackFrame {
  const PlaybackFrame_PixelBuffer(this.field0): super._();
  

@override final  PreviewFramePixelBuffer field0;

/// Create a copy of PlaybackFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlaybackFrame_PixelBufferCopyWith<PlaybackFrame_PixelBuffer> get copyWith => _$PlaybackFrame_PixelBufferCopyWithImpl<PlaybackFrame_PixelBuffer>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlaybackFrame_PixelBuffer&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'PlaybackFrame.pixelBuffer(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $PlaybackFrame_PixelBufferCopyWith<$Res> implements $PlaybackFrameCopyWith<$Res> {
  factory $PlaybackFrame_PixelBufferCopyWith(PlaybackFrame_PixelBuffer value, $Res Function(PlaybackFrame_PixelBuffer) _then) = _$PlaybackFrame_PixelBufferCopyWithImpl;
@useResult
$Res call({
 PreviewFramePixelBuffer field0
});




}
/// @nodoc
class _$PlaybackFrame_PixelBufferCopyWithImpl<$Res>
    implements $PlaybackFrame_PixelBufferCopyWith<$Res> {
  _$PlaybackFrame_PixelBufferCopyWithImpl(this._self, this._then);

  final PlaybackFrame_PixelBuffer _self;
  final $Res Function(PlaybackFrame_PixelBuffer) _then;

/// Create a copy of PlaybackFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(PlaybackFrame_PixelBuffer(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as PreviewFramePixelBuffer,
  ));
}


}

// dart format on
