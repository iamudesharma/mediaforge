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
mixin _$OutputProfile {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OutputProfile);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'OutputProfile()';
}


}

/// @nodoc
class $OutputProfileCopyWith<$Res>  {
$OutputProfileCopyWith(OutputProfile _, $Res Function(OutputProfile) __);
}


/// Adds pattern-matching-related methods to [OutputProfile].
extension OutputProfilePatterns on OutputProfile {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( OutputProfile_ProgressiveMp4 value)?  progressiveMp4,TResult Function( OutputProfile_FragmentedMp4 value)?  fragmentedMp4,TResult Function( OutputProfile_Hls value)?  hls,required TResult orElse(),}){
final _that = this;
switch (_that) {
case OutputProfile_ProgressiveMp4() when progressiveMp4 != null:
return progressiveMp4(_that);case OutputProfile_FragmentedMp4() when fragmentedMp4 != null:
return fragmentedMp4(_that);case OutputProfile_Hls() when hls != null:
return hls(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( OutputProfile_ProgressiveMp4 value)  progressiveMp4,required TResult Function( OutputProfile_FragmentedMp4 value)  fragmentedMp4,required TResult Function( OutputProfile_Hls value)  hls,}){
final _that = this;
switch (_that) {
case OutputProfile_ProgressiveMp4():
return progressiveMp4(_that);case OutputProfile_FragmentedMp4():
return fragmentedMp4(_that);case OutputProfile_Hls():
return hls(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( OutputProfile_ProgressiveMp4 value)?  progressiveMp4,TResult? Function( OutputProfile_FragmentedMp4 value)?  fragmentedMp4,TResult? Function( OutputProfile_Hls value)?  hls,}){
final _that = this;
switch (_that) {
case OutputProfile_ProgressiveMp4() when progressiveMp4 != null:
return progressiveMp4(_that);case OutputProfile_FragmentedMp4() when fragmentedMp4 != null:
return fragmentedMp4(_that);case OutputProfile_Hls() when hls != null:
return hls(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( bool fastStart)?  progressiveMp4,TResult Function( int fragmentDurationMs)?  fragmentedMp4,TResult Function( int segmentDurationMs,  bool masterPlaylist,  int hlsVersion)?  hls,required TResult orElse(),}) {final _that = this;
switch (_that) {
case OutputProfile_ProgressiveMp4() when progressiveMp4 != null:
return progressiveMp4(_that.fastStart);case OutputProfile_FragmentedMp4() when fragmentedMp4 != null:
return fragmentedMp4(_that.fragmentDurationMs);case OutputProfile_Hls() when hls != null:
return hls(_that.segmentDurationMs,_that.masterPlaylist,_that.hlsVersion);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( bool fastStart)  progressiveMp4,required TResult Function( int fragmentDurationMs)  fragmentedMp4,required TResult Function( int segmentDurationMs,  bool masterPlaylist,  int hlsVersion)  hls,}) {final _that = this;
switch (_that) {
case OutputProfile_ProgressiveMp4():
return progressiveMp4(_that.fastStart);case OutputProfile_FragmentedMp4():
return fragmentedMp4(_that.fragmentDurationMs);case OutputProfile_Hls():
return hls(_that.segmentDurationMs,_that.masterPlaylist,_that.hlsVersion);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( bool fastStart)?  progressiveMp4,TResult? Function( int fragmentDurationMs)?  fragmentedMp4,TResult? Function( int segmentDurationMs,  bool masterPlaylist,  int hlsVersion)?  hls,}) {final _that = this;
switch (_that) {
case OutputProfile_ProgressiveMp4() when progressiveMp4 != null:
return progressiveMp4(_that.fastStart);case OutputProfile_FragmentedMp4() when fragmentedMp4 != null:
return fragmentedMp4(_that.fragmentDurationMs);case OutputProfile_Hls() when hls != null:
return hls(_that.segmentDurationMs,_that.masterPlaylist,_that.hlsVersion);case _:
  return null;

}
}

}

/// @nodoc


class OutputProfile_ProgressiveMp4 extends OutputProfile {
  const OutputProfile_ProgressiveMp4({required this.fastStart}): super._();
  

/// Move the moov atom to the front of the file so playback
/// can start before the download completes. Default: `true`.
 final  bool fastStart;

/// Create a copy of OutputProfile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OutputProfile_ProgressiveMp4CopyWith<OutputProfile_ProgressiveMp4> get copyWith => _$OutputProfile_ProgressiveMp4CopyWithImpl<OutputProfile_ProgressiveMp4>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OutputProfile_ProgressiveMp4&&(identical(other.fastStart, fastStart) || other.fastStart == fastStart));
}


@override
int get hashCode => Object.hash(runtimeType,fastStart);

@override
String toString() {
  return 'OutputProfile.progressiveMp4(fastStart: $fastStart)';
}


}

/// @nodoc
abstract mixin class $OutputProfile_ProgressiveMp4CopyWith<$Res> implements $OutputProfileCopyWith<$Res> {
  factory $OutputProfile_ProgressiveMp4CopyWith(OutputProfile_ProgressiveMp4 value, $Res Function(OutputProfile_ProgressiveMp4) _then) = _$OutputProfile_ProgressiveMp4CopyWithImpl;
@useResult
$Res call({
 bool fastStart
});




}
/// @nodoc
class _$OutputProfile_ProgressiveMp4CopyWithImpl<$Res>
    implements $OutputProfile_ProgressiveMp4CopyWith<$Res> {
  _$OutputProfile_ProgressiveMp4CopyWithImpl(this._self, this._then);

  final OutputProfile_ProgressiveMp4 _self;
  final $Res Function(OutputProfile_ProgressiveMp4) _then;

/// Create a copy of OutputProfile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? fastStart = null,}) {
  return _then(OutputProfile_ProgressiveMp4(
fastStart: null == fastStart ? _self.fastStart : fastStart // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class OutputProfile_FragmentedMp4 extends OutputProfile {
  const OutputProfile_FragmentedMp4({required this.fragmentDurationMs}): super._();
  

/// Target fragment length in milliseconds. Default: `2000`
/// (matches the HLS default segment length).
 final  int fragmentDurationMs;

/// Create a copy of OutputProfile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OutputProfile_FragmentedMp4CopyWith<OutputProfile_FragmentedMp4> get copyWith => _$OutputProfile_FragmentedMp4CopyWithImpl<OutputProfile_FragmentedMp4>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OutputProfile_FragmentedMp4&&(identical(other.fragmentDurationMs, fragmentDurationMs) || other.fragmentDurationMs == fragmentDurationMs));
}


@override
int get hashCode => Object.hash(runtimeType,fragmentDurationMs);

@override
String toString() {
  return 'OutputProfile.fragmentedMp4(fragmentDurationMs: $fragmentDurationMs)';
}


}

/// @nodoc
abstract mixin class $OutputProfile_FragmentedMp4CopyWith<$Res> implements $OutputProfileCopyWith<$Res> {
  factory $OutputProfile_FragmentedMp4CopyWith(OutputProfile_FragmentedMp4 value, $Res Function(OutputProfile_FragmentedMp4) _then) = _$OutputProfile_FragmentedMp4CopyWithImpl;
@useResult
$Res call({
 int fragmentDurationMs
});




}
/// @nodoc
class _$OutputProfile_FragmentedMp4CopyWithImpl<$Res>
    implements $OutputProfile_FragmentedMp4CopyWith<$Res> {
  _$OutputProfile_FragmentedMp4CopyWithImpl(this._self, this._then);

  final OutputProfile_FragmentedMp4 _self;
  final $Res Function(OutputProfile_FragmentedMp4) _then;

/// Create a copy of OutputProfile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? fragmentDurationMs = null,}) {
  return _then(OutputProfile_FragmentedMp4(
fragmentDurationMs: null == fragmentDurationMs ? _self.fragmentDurationMs : fragmentDurationMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class OutputProfile_Hls extends OutputProfile {
  const OutputProfile_Hls({required this.segmentDurationMs, required this.masterPlaylist, required this.hlsVersion}): super._();
  

/// Target segment length in milliseconds. Default: `6000`
/// (Apple's recommended HLS segment length).
 final  int segmentDurationMs;
/// When `true`, FFmpeg also writes a `master.m3u8` with
/// `#EXT-X-STREAM-INF` tags for adaptive bitrate ladders.
/// Currently a single rendition is emitted; the master
/// playlist is correct in shape but lists only one variant.
 final  bool masterPlaylist;
/// HLS protocol version. Default: `6` (HLSv6, supports
/// fMP4 / CMAF segments). Use `3` for legacy clients.
 final  int hlsVersion;

/// Create a copy of OutputProfile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OutputProfile_HlsCopyWith<OutputProfile_Hls> get copyWith => _$OutputProfile_HlsCopyWithImpl<OutputProfile_Hls>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OutputProfile_Hls&&(identical(other.segmentDurationMs, segmentDurationMs) || other.segmentDurationMs == segmentDurationMs)&&(identical(other.masterPlaylist, masterPlaylist) || other.masterPlaylist == masterPlaylist)&&(identical(other.hlsVersion, hlsVersion) || other.hlsVersion == hlsVersion));
}


@override
int get hashCode => Object.hash(runtimeType,segmentDurationMs,masterPlaylist,hlsVersion);

@override
String toString() {
  return 'OutputProfile.hls(segmentDurationMs: $segmentDurationMs, masterPlaylist: $masterPlaylist, hlsVersion: $hlsVersion)';
}


}

/// @nodoc
abstract mixin class $OutputProfile_HlsCopyWith<$Res> implements $OutputProfileCopyWith<$Res> {
  factory $OutputProfile_HlsCopyWith(OutputProfile_Hls value, $Res Function(OutputProfile_Hls) _then) = _$OutputProfile_HlsCopyWithImpl;
@useResult
$Res call({
 int segmentDurationMs, bool masterPlaylist, int hlsVersion
});




}
/// @nodoc
class _$OutputProfile_HlsCopyWithImpl<$Res>
    implements $OutputProfile_HlsCopyWith<$Res> {
  _$OutputProfile_HlsCopyWithImpl(this._self, this._then);

  final OutputProfile_Hls _self;
  final $Res Function(OutputProfile_Hls) _then;

/// Create a copy of OutputProfile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? segmentDurationMs = null,Object? masterPlaylist = null,Object? hlsVersion = null,}) {
  return _then(OutputProfile_Hls(
segmentDurationMs: null == segmentDurationMs ? _self.segmentDurationMs : segmentDurationMs // ignore: cast_nullable_to_non_nullable
as int,masterPlaylist: null == masterPlaylist ? _self.masterPlaylist : masterPlaylist // ignore: cast_nullable_to_non_nullable
as bool,hlsVersion: null == hlsVersion ? _self.hlsVersion : hlsVersion // ignore: cast_nullable_to_non_nullable
as int,
  ));
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
