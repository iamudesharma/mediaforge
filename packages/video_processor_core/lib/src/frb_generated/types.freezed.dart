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




// dart format on
