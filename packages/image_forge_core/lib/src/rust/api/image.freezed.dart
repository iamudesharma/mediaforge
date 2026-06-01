// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'image.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$EditOp {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EditOp);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'EditOp()';
}


}

/// @nodoc
class $EditOpCopyWith<$Res>  {
$EditOpCopyWith(EditOp _, $Res Function(EditOp) __);
}


/// Adds pattern-matching-related methods to [EditOp].
extension EditOpPatterns on EditOp {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( EditOp_Filter value)?  filter,TResult Function( EditOp_Resize value)?  resize,TResult Function( EditOp_Crop value)?  crop,TResult Function( EditOp_Rotate value)?  rotate,required TResult orElse(),}){
final _that = this;
switch (_that) {
case EditOp_Filter() when filter != null:
return filter(_that);case EditOp_Resize() when resize != null:
return resize(_that);case EditOp_Crop() when crop != null:
return crop(_that);case EditOp_Rotate() when rotate != null:
return rotate(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( EditOp_Filter value)  filter,required TResult Function( EditOp_Resize value)  resize,required TResult Function( EditOp_Crop value)  crop,required TResult Function( EditOp_Rotate value)  rotate,}){
final _that = this;
switch (_that) {
case EditOp_Filter():
return filter(_that);case EditOp_Resize():
return resize(_that);case EditOp_Crop():
return crop(_that);case EditOp_Rotate():
return rotate(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( EditOp_Filter value)?  filter,TResult? Function( EditOp_Resize value)?  resize,TResult? Function( EditOp_Crop value)?  crop,TResult? Function( EditOp_Rotate value)?  rotate,}){
final _that = this;
switch (_that) {
case EditOp_Filter() when filter != null:
return filter(_that);case EditOp_Resize() when resize != null:
return resize(_that);case EditOp_Crop() when crop != null:
return crop(_that);case EditOp_Rotate() when rotate != null:
return rotate(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ImageFilter filter)?  filter,TResult Function( int width,  int height,  ResizeAlgorithm algorithm)?  resize,TResult Function( int x,  int y,  int width,  int height)?  crop,TResult Function( Rotation rotation)?  rotate,required TResult orElse(),}) {final _that = this;
switch (_that) {
case EditOp_Filter() when filter != null:
return filter(_that.filter);case EditOp_Resize() when resize != null:
return resize(_that.width,_that.height,_that.algorithm);case EditOp_Crop() when crop != null:
return crop(_that.x,_that.y,_that.width,_that.height);case EditOp_Rotate() when rotate != null:
return rotate(_that.rotation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ImageFilter filter)  filter,required TResult Function( int width,  int height,  ResizeAlgorithm algorithm)  resize,required TResult Function( int x,  int y,  int width,  int height)  crop,required TResult Function( Rotation rotation)  rotate,}) {final _that = this;
switch (_that) {
case EditOp_Filter():
return filter(_that.filter);case EditOp_Resize():
return resize(_that.width,_that.height,_that.algorithm);case EditOp_Crop():
return crop(_that.x,_that.y,_that.width,_that.height);case EditOp_Rotate():
return rotate(_that.rotation);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ImageFilter filter)?  filter,TResult? Function( int width,  int height,  ResizeAlgorithm algorithm)?  resize,TResult? Function( int x,  int y,  int width,  int height)?  crop,TResult? Function( Rotation rotation)?  rotate,}) {final _that = this;
switch (_that) {
case EditOp_Filter() when filter != null:
return filter(_that.filter);case EditOp_Resize() when resize != null:
return resize(_that.width,_that.height,_that.algorithm);case EditOp_Crop() when crop != null:
return crop(_that.x,_that.y,_that.width,_that.height);case EditOp_Rotate() when rotate != null:
return rotate(_that.rotation);case _:
  return null;

}
}

}

/// @nodoc


class EditOp_Filter extends EditOp {
  const EditOp_Filter({required this.filter}): super._();
  

 final  ImageFilter filter;

/// Create a copy of EditOp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditOp_FilterCopyWith<EditOp_Filter> get copyWith => _$EditOp_FilterCopyWithImpl<EditOp_Filter>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EditOp_Filter&&(identical(other.filter, filter) || other.filter == filter));
}


@override
int get hashCode => Object.hash(runtimeType,filter);

@override
String toString() {
  return 'EditOp.filter(filter: $filter)';
}


}

/// @nodoc
abstract mixin class $EditOp_FilterCopyWith<$Res> implements $EditOpCopyWith<$Res> {
  factory $EditOp_FilterCopyWith(EditOp_Filter value, $Res Function(EditOp_Filter) _then) = _$EditOp_FilterCopyWithImpl;
@useResult
$Res call({
 ImageFilter filter
});


$ImageFilterCopyWith<$Res> get filter;

}
/// @nodoc
class _$EditOp_FilterCopyWithImpl<$Res>
    implements $EditOp_FilterCopyWith<$Res> {
  _$EditOp_FilterCopyWithImpl(this._self, this._then);

  final EditOp_Filter _self;
  final $Res Function(EditOp_Filter) _then;

/// Create a copy of EditOp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? filter = null,}) {
  return _then(EditOp_Filter(
filter: null == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as ImageFilter,
  ));
}

/// Create a copy of EditOp
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ImageFilterCopyWith<$Res> get filter {
  
  return $ImageFilterCopyWith<$Res>(_self.filter, (value) {
    return _then(_self.copyWith(filter: value));
  });
}
}

/// @nodoc


class EditOp_Resize extends EditOp {
  const EditOp_Resize({required this.width, required this.height, required this.algorithm}): super._();
  

 final  int width;
 final  int height;
 final  ResizeAlgorithm algorithm;

/// Create a copy of EditOp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditOp_ResizeCopyWith<EditOp_Resize> get copyWith => _$EditOp_ResizeCopyWithImpl<EditOp_Resize>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EditOp_Resize&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.algorithm, algorithm) || other.algorithm == algorithm));
}


@override
int get hashCode => Object.hash(runtimeType,width,height,algorithm);

@override
String toString() {
  return 'EditOp.resize(width: $width, height: $height, algorithm: $algorithm)';
}


}

/// @nodoc
abstract mixin class $EditOp_ResizeCopyWith<$Res> implements $EditOpCopyWith<$Res> {
  factory $EditOp_ResizeCopyWith(EditOp_Resize value, $Res Function(EditOp_Resize) _then) = _$EditOp_ResizeCopyWithImpl;
@useResult
$Res call({
 int width, int height, ResizeAlgorithm algorithm
});




}
/// @nodoc
class _$EditOp_ResizeCopyWithImpl<$Res>
    implements $EditOp_ResizeCopyWith<$Res> {
  _$EditOp_ResizeCopyWithImpl(this._self, this._then);

  final EditOp_Resize _self;
  final $Res Function(EditOp_Resize) _then;

/// Create a copy of EditOp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? width = null,Object? height = null,Object? algorithm = null,}) {
  return _then(EditOp_Resize(
width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int,algorithm: null == algorithm ? _self.algorithm : algorithm // ignore: cast_nullable_to_non_nullable
as ResizeAlgorithm,
  ));
}


}

/// @nodoc


class EditOp_Crop extends EditOp {
  const EditOp_Crop({required this.x, required this.y, required this.width, required this.height}): super._();
  

 final  int x;
 final  int y;
 final  int width;
 final  int height;

/// Create a copy of EditOp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditOp_CropCopyWith<EditOp_Crop> get copyWith => _$EditOp_CropCopyWithImpl<EditOp_Crop>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EditOp_Crop&&(identical(other.x, x) || other.x == x)&&(identical(other.y, y) || other.y == y)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height));
}


@override
int get hashCode => Object.hash(runtimeType,x,y,width,height);

@override
String toString() {
  return 'EditOp.crop(x: $x, y: $y, width: $width, height: $height)';
}


}

/// @nodoc
abstract mixin class $EditOp_CropCopyWith<$Res> implements $EditOpCopyWith<$Res> {
  factory $EditOp_CropCopyWith(EditOp_Crop value, $Res Function(EditOp_Crop) _then) = _$EditOp_CropCopyWithImpl;
@useResult
$Res call({
 int x, int y, int width, int height
});




}
/// @nodoc
class _$EditOp_CropCopyWithImpl<$Res>
    implements $EditOp_CropCopyWith<$Res> {
  _$EditOp_CropCopyWithImpl(this._self, this._then);

  final EditOp_Crop _self;
  final $Res Function(EditOp_Crop) _then;

/// Create a copy of EditOp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? x = null,Object? y = null,Object? width = null,Object? height = null,}) {
  return _then(EditOp_Crop(
x: null == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as int,y: null == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as int,width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class EditOp_Rotate extends EditOp {
  const EditOp_Rotate({required this.rotation}): super._();
  

 final  Rotation rotation;

/// Create a copy of EditOp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditOp_RotateCopyWith<EditOp_Rotate> get copyWith => _$EditOp_RotateCopyWithImpl<EditOp_Rotate>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EditOp_Rotate&&(identical(other.rotation, rotation) || other.rotation == rotation));
}


@override
int get hashCode => Object.hash(runtimeType,rotation);

@override
String toString() {
  return 'EditOp.rotate(rotation: $rotation)';
}


}

/// @nodoc
abstract mixin class $EditOp_RotateCopyWith<$Res> implements $EditOpCopyWith<$Res> {
  factory $EditOp_RotateCopyWith(EditOp_Rotate value, $Res Function(EditOp_Rotate) _then) = _$EditOp_RotateCopyWithImpl;
@useResult
$Res call({
 Rotation rotation
});




}
/// @nodoc
class _$EditOp_RotateCopyWithImpl<$Res>
    implements $EditOp_RotateCopyWith<$Res> {
  _$EditOp_RotateCopyWithImpl(this._self, this._then);

  final EditOp_Rotate _self;
  final $Res Function(EditOp_Rotate) _then;

/// Create a copy of EditOp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? rotation = null,}) {
  return _then(EditOp_Rotate(
rotation: null == rotation ? _self.rotation : rotation // ignore: cast_nullable_to_non_nullable
as Rotation,
  ));
}


}

/// @nodoc
mixin _$ImageFilter {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ImageFilter()';
}


}

/// @nodoc
class $ImageFilterCopyWith<$Res>  {
$ImageFilterCopyWith(ImageFilter _, $Res Function(ImageFilter) __);
}


/// Adds pattern-matching-related methods to [ImageFilter].
extension ImageFilterPatterns on ImageFilter {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ImageFilter_Blur value)?  blur,TResult Function( ImageFilter_Sharpen value)?  sharpen,TResult Function( ImageFilter_Brightness value)?  brightness,TResult Function( ImageFilter_Contrast value)?  contrast,TResult Function( ImageFilter_Saturation value)?  saturation,TResult Function( ImageFilter_HueRotate value)?  hueRotate,TResult Function( ImageFilter_Oil value)?  oil,TResult Function( ImageFilter_FrostedGlass value)?  frostedGlass,TResult Function( ImageFilter_Pixelize value)?  pixelize,TResult Function( ImageFilter_Solarize value)?  solarize,TResult Function( ImageFilter_Preset value)?  preset,TResult Function( ImageFilter_Warmth value)?  warmth,TResult Function( ImageFilter_Fade value)?  fade,TResult Function( ImageFilter_Vignette value)?  vignette,TResult Function( ImageFilter_Highlights value)?  highlights,TResult Function( ImageFilter_Shadows value)?  shadows,TResult Function( ImageFilter_Structure value)?  structure,TResult Function( ImageFilter_Mood value)?  mood,TResult Function( ImageFilter_SwipeLook value)?  swipeLook,TResult Function( ImageFilter_LutPng value)?  lutPng,TResult Function( ImageFilter_SkinSmooth value)?  skinSmooth,TResult Function( ImageFilter_Beauty value)?  beauty,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ImageFilter_Blur() when blur != null:
return blur(_that);case ImageFilter_Sharpen() when sharpen != null:
return sharpen(_that);case ImageFilter_Brightness() when brightness != null:
return brightness(_that);case ImageFilter_Contrast() when contrast != null:
return contrast(_that);case ImageFilter_Saturation() when saturation != null:
return saturation(_that);case ImageFilter_HueRotate() when hueRotate != null:
return hueRotate(_that);case ImageFilter_Oil() when oil != null:
return oil(_that);case ImageFilter_FrostedGlass() when frostedGlass != null:
return frostedGlass(_that);case ImageFilter_Pixelize() when pixelize != null:
return pixelize(_that);case ImageFilter_Solarize() when solarize != null:
return solarize(_that);case ImageFilter_Preset() when preset != null:
return preset(_that);case ImageFilter_Warmth() when warmth != null:
return warmth(_that);case ImageFilter_Fade() when fade != null:
return fade(_that);case ImageFilter_Vignette() when vignette != null:
return vignette(_that);case ImageFilter_Highlights() when highlights != null:
return highlights(_that);case ImageFilter_Shadows() when shadows != null:
return shadows(_that);case ImageFilter_Structure() when structure != null:
return structure(_that);case ImageFilter_Mood() when mood != null:
return mood(_that);case ImageFilter_SwipeLook() when swipeLook != null:
return swipeLook(_that);case ImageFilter_LutPng() when lutPng != null:
return lutPng(_that);case ImageFilter_SkinSmooth() when skinSmooth != null:
return skinSmooth(_that);case ImageFilter_Beauty() when beauty != null:
return beauty(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ImageFilter_Blur value)  blur,required TResult Function( ImageFilter_Sharpen value)  sharpen,required TResult Function( ImageFilter_Brightness value)  brightness,required TResult Function( ImageFilter_Contrast value)  contrast,required TResult Function( ImageFilter_Saturation value)  saturation,required TResult Function( ImageFilter_HueRotate value)  hueRotate,required TResult Function( ImageFilter_Oil value)  oil,required TResult Function( ImageFilter_FrostedGlass value)  frostedGlass,required TResult Function( ImageFilter_Pixelize value)  pixelize,required TResult Function( ImageFilter_Solarize value)  solarize,required TResult Function( ImageFilter_Preset value)  preset,required TResult Function( ImageFilter_Warmth value)  warmth,required TResult Function( ImageFilter_Fade value)  fade,required TResult Function( ImageFilter_Vignette value)  vignette,required TResult Function( ImageFilter_Highlights value)  highlights,required TResult Function( ImageFilter_Shadows value)  shadows,required TResult Function( ImageFilter_Structure value)  structure,required TResult Function( ImageFilter_Mood value)  mood,required TResult Function( ImageFilter_SwipeLook value)  swipeLook,required TResult Function( ImageFilter_LutPng value)  lutPng,required TResult Function( ImageFilter_SkinSmooth value)  skinSmooth,required TResult Function( ImageFilter_Beauty value)  beauty,}){
final _that = this;
switch (_that) {
case ImageFilter_Blur():
return blur(_that);case ImageFilter_Sharpen():
return sharpen(_that);case ImageFilter_Brightness():
return brightness(_that);case ImageFilter_Contrast():
return contrast(_that);case ImageFilter_Saturation():
return saturation(_that);case ImageFilter_HueRotate():
return hueRotate(_that);case ImageFilter_Oil():
return oil(_that);case ImageFilter_FrostedGlass():
return frostedGlass(_that);case ImageFilter_Pixelize():
return pixelize(_that);case ImageFilter_Solarize():
return solarize(_that);case ImageFilter_Preset():
return preset(_that);case ImageFilter_Warmth():
return warmth(_that);case ImageFilter_Fade():
return fade(_that);case ImageFilter_Vignette():
return vignette(_that);case ImageFilter_Highlights():
return highlights(_that);case ImageFilter_Shadows():
return shadows(_that);case ImageFilter_Structure():
return structure(_that);case ImageFilter_Mood():
return mood(_that);case ImageFilter_SwipeLook():
return swipeLook(_that);case ImageFilter_LutPng():
return lutPng(_that);case ImageFilter_SkinSmooth():
return skinSmooth(_that);case ImageFilter_Beauty():
return beauty(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ImageFilter_Blur value)?  blur,TResult? Function( ImageFilter_Sharpen value)?  sharpen,TResult? Function( ImageFilter_Brightness value)?  brightness,TResult? Function( ImageFilter_Contrast value)?  contrast,TResult? Function( ImageFilter_Saturation value)?  saturation,TResult? Function( ImageFilter_HueRotate value)?  hueRotate,TResult? Function( ImageFilter_Oil value)?  oil,TResult? Function( ImageFilter_FrostedGlass value)?  frostedGlass,TResult? Function( ImageFilter_Pixelize value)?  pixelize,TResult? Function( ImageFilter_Solarize value)?  solarize,TResult? Function( ImageFilter_Preset value)?  preset,TResult? Function( ImageFilter_Warmth value)?  warmth,TResult? Function( ImageFilter_Fade value)?  fade,TResult? Function( ImageFilter_Vignette value)?  vignette,TResult? Function( ImageFilter_Highlights value)?  highlights,TResult? Function( ImageFilter_Shadows value)?  shadows,TResult? Function( ImageFilter_Structure value)?  structure,TResult? Function( ImageFilter_Mood value)?  mood,TResult? Function( ImageFilter_SwipeLook value)?  swipeLook,TResult? Function( ImageFilter_LutPng value)?  lutPng,TResult? Function( ImageFilter_SkinSmooth value)?  skinSmooth,TResult? Function( ImageFilter_Beauty value)?  beauty,}){
final _that = this;
switch (_that) {
case ImageFilter_Blur() when blur != null:
return blur(_that);case ImageFilter_Sharpen() when sharpen != null:
return sharpen(_that);case ImageFilter_Brightness() when brightness != null:
return brightness(_that);case ImageFilter_Contrast() when contrast != null:
return contrast(_that);case ImageFilter_Saturation() when saturation != null:
return saturation(_that);case ImageFilter_HueRotate() when hueRotate != null:
return hueRotate(_that);case ImageFilter_Oil() when oil != null:
return oil(_that);case ImageFilter_FrostedGlass() when frostedGlass != null:
return frostedGlass(_that);case ImageFilter_Pixelize() when pixelize != null:
return pixelize(_that);case ImageFilter_Solarize() when solarize != null:
return solarize(_that);case ImageFilter_Preset() when preset != null:
return preset(_that);case ImageFilter_Warmth() when warmth != null:
return warmth(_that);case ImageFilter_Fade() when fade != null:
return fade(_that);case ImageFilter_Vignette() when vignette != null:
return vignette(_that);case ImageFilter_Highlights() when highlights != null:
return highlights(_that);case ImageFilter_Shadows() when shadows != null:
return shadows(_that);case ImageFilter_Structure() when structure != null:
return structure(_that);case ImageFilter_Mood() when mood != null:
return mood(_that);case ImageFilter_SwipeLook() when swipeLook != null:
return swipeLook(_that);case ImageFilter_LutPng() when lutPng != null:
return lutPng(_that);case ImageFilter_SkinSmooth() when skinSmooth != null:
return skinSmooth(_that);case ImageFilter_Beauty() when beauty != null:
return beauty(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int radius)?  blur,TResult Function()?  sharpen,TResult Function( int amount)?  brightness,TResult Function( double amount)?  contrast,TResult Function( double amount)?  saturation,TResult Function( double degrees)?  hueRotate,TResult Function( int radius,  double intensity)?  oil,TResult Function()?  frostedGlass,TResult Function( int size)?  pixelize,TResult Function()?  solarize,TResult Function( FilterPreset preset,  double strength)?  preset,TResult Function( double amount)?  warmth,TResult Function( double amount)?  fade,TResult Function( double amount)?  vignette,TResult Function( double amount)?  highlights,TResult Function( double amount)?  shadows,TResult Function( double amount)?  structure,TResult Function( MoodFilterPreset preset,  double strength)?  mood,TResult Function( SwipeLookPreset preset,  double strength)?  swipeLook,TResult Function( Uint8List pngBytes,  double strength)?  lutPng,TResult Function( double strength)?  skinSmooth,TResult Function( BeautyParams params)?  beauty,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ImageFilter_Blur() when blur != null:
return blur(_that.radius);case ImageFilter_Sharpen() when sharpen != null:
return sharpen();case ImageFilter_Brightness() when brightness != null:
return brightness(_that.amount);case ImageFilter_Contrast() when contrast != null:
return contrast(_that.amount);case ImageFilter_Saturation() when saturation != null:
return saturation(_that.amount);case ImageFilter_HueRotate() when hueRotate != null:
return hueRotate(_that.degrees);case ImageFilter_Oil() when oil != null:
return oil(_that.radius,_that.intensity);case ImageFilter_FrostedGlass() when frostedGlass != null:
return frostedGlass();case ImageFilter_Pixelize() when pixelize != null:
return pixelize(_that.size);case ImageFilter_Solarize() when solarize != null:
return solarize();case ImageFilter_Preset() when preset != null:
return preset(_that.preset,_that.strength);case ImageFilter_Warmth() when warmth != null:
return warmth(_that.amount);case ImageFilter_Fade() when fade != null:
return fade(_that.amount);case ImageFilter_Vignette() when vignette != null:
return vignette(_that.amount);case ImageFilter_Highlights() when highlights != null:
return highlights(_that.amount);case ImageFilter_Shadows() when shadows != null:
return shadows(_that.amount);case ImageFilter_Structure() when structure != null:
return structure(_that.amount);case ImageFilter_Mood() when mood != null:
return mood(_that.preset,_that.strength);case ImageFilter_SwipeLook() when swipeLook != null:
return swipeLook(_that.preset,_that.strength);case ImageFilter_LutPng() when lutPng != null:
return lutPng(_that.pngBytes,_that.strength);case ImageFilter_SkinSmooth() when skinSmooth != null:
return skinSmooth(_that.strength);case ImageFilter_Beauty() when beauty != null:
return beauty(_that.params);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int radius)  blur,required TResult Function()  sharpen,required TResult Function( int amount)  brightness,required TResult Function( double amount)  contrast,required TResult Function( double amount)  saturation,required TResult Function( double degrees)  hueRotate,required TResult Function( int radius,  double intensity)  oil,required TResult Function()  frostedGlass,required TResult Function( int size)  pixelize,required TResult Function()  solarize,required TResult Function( FilterPreset preset,  double strength)  preset,required TResult Function( double amount)  warmth,required TResult Function( double amount)  fade,required TResult Function( double amount)  vignette,required TResult Function( double amount)  highlights,required TResult Function( double amount)  shadows,required TResult Function( double amount)  structure,required TResult Function( MoodFilterPreset preset,  double strength)  mood,required TResult Function( SwipeLookPreset preset,  double strength)  swipeLook,required TResult Function( Uint8List pngBytes,  double strength)  lutPng,required TResult Function( double strength)  skinSmooth,required TResult Function( BeautyParams params)  beauty,}) {final _that = this;
switch (_that) {
case ImageFilter_Blur():
return blur(_that.radius);case ImageFilter_Sharpen():
return sharpen();case ImageFilter_Brightness():
return brightness(_that.amount);case ImageFilter_Contrast():
return contrast(_that.amount);case ImageFilter_Saturation():
return saturation(_that.amount);case ImageFilter_HueRotate():
return hueRotate(_that.degrees);case ImageFilter_Oil():
return oil(_that.radius,_that.intensity);case ImageFilter_FrostedGlass():
return frostedGlass();case ImageFilter_Pixelize():
return pixelize(_that.size);case ImageFilter_Solarize():
return solarize();case ImageFilter_Preset():
return preset(_that.preset,_that.strength);case ImageFilter_Warmth():
return warmth(_that.amount);case ImageFilter_Fade():
return fade(_that.amount);case ImageFilter_Vignette():
return vignette(_that.amount);case ImageFilter_Highlights():
return highlights(_that.amount);case ImageFilter_Shadows():
return shadows(_that.amount);case ImageFilter_Structure():
return structure(_that.amount);case ImageFilter_Mood():
return mood(_that.preset,_that.strength);case ImageFilter_SwipeLook():
return swipeLook(_that.preset,_that.strength);case ImageFilter_LutPng():
return lutPng(_that.pngBytes,_that.strength);case ImageFilter_SkinSmooth():
return skinSmooth(_that.strength);case ImageFilter_Beauty():
return beauty(_that.params);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int radius)?  blur,TResult? Function()?  sharpen,TResult? Function( int amount)?  brightness,TResult? Function( double amount)?  contrast,TResult? Function( double amount)?  saturation,TResult? Function( double degrees)?  hueRotate,TResult? Function( int radius,  double intensity)?  oil,TResult? Function()?  frostedGlass,TResult? Function( int size)?  pixelize,TResult? Function()?  solarize,TResult? Function( FilterPreset preset,  double strength)?  preset,TResult? Function( double amount)?  warmth,TResult? Function( double amount)?  fade,TResult? Function( double amount)?  vignette,TResult? Function( double amount)?  highlights,TResult? Function( double amount)?  shadows,TResult? Function( double amount)?  structure,TResult? Function( MoodFilterPreset preset,  double strength)?  mood,TResult? Function( SwipeLookPreset preset,  double strength)?  swipeLook,TResult? Function( Uint8List pngBytes,  double strength)?  lutPng,TResult? Function( double strength)?  skinSmooth,TResult? Function( BeautyParams params)?  beauty,}) {final _that = this;
switch (_that) {
case ImageFilter_Blur() when blur != null:
return blur(_that.radius);case ImageFilter_Sharpen() when sharpen != null:
return sharpen();case ImageFilter_Brightness() when brightness != null:
return brightness(_that.amount);case ImageFilter_Contrast() when contrast != null:
return contrast(_that.amount);case ImageFilter_Saturation() when saturation != null:
return saturation(_that.amount);case ImageFilter_HueRotate() when hueRotate != null:
return hueRotate(_that.degrees);case ImageFilter_Oil() when oil != null:
return oil(_that.radius,_that.intensity);case ImageFilter_FrostedGlass() when frostedGlass != null:
return frostedGlass();case ImageFilter_Pixelize() when pixelize != null:
return pixelize(_that.size);case ImageFilter_Solarize() when solarize != null:
return solarize();case ImageFilter_Preset() when preset != null:
return preset(_that.preset,_that.strength);case ImageFilter_Warmth() when warmth != null:
return warmth(_that.amount);case ImageFilter_Fade() when fade != null:
return fade(_that.amount);case ImageFilter_Vignette() when vignette != null:
return vignette(_that.amount);case ImageFilter_Highlights() when highlights != null:
return highlights(_that.amount);case ImageFilter_Shadows() when shadows != null:
return shadows(_that.amount);case ImageFilter_Structure() when structure != null:
return structure(_that.amount);case ImageFilter_Mood() when mood != null:
return mood(_that.preset,_that.strength);case ImageFilter_SwipeLook() when swipeLook != null:
return swipeLook(_that.preset,_that.strength);case ImageFilter_LutPng() when lutPng != null:
return lutPng(_that.pngBytes,_that.strength);case ImageFilter_SkinSmooth() when skinSmooth != null:
return skinSmooth(_that.strength);case ImageFilter_Beauty() when beauty != null:
return beauty(_that.params);case _:
  return null;

}
}

}

/// @nodoc


class ImageFilter_Blur extends ImageFilter {
  const ImageFilter_Blur({required this.radius}): super._();
  

 final  int radius;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_BlurCopyWith<ImageFilter_Blur> get copyWith => _$ImageFilter_BlurCopyWithImpl<ImageFilter_Blur>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_Blur&&(identical(other.radius, radius) || other.radius == radius));
}


@override
int get hashCode => Object.hash(runtimeType,radius);

@override
String toString() {
  return 'ImageFilter.blur(radius: $radius)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_BlurCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_BlurCopyWith(ImageFilter_Blur value, $Res Function(ImageFilter_Blur) _then) = _$ImageFilter_BlurCopyWithImpl;
@useResult
$Res call({
 int radius
});




}
/// @nodoc
class _$ImageFilter_BlurCopyWithImpl<$Res>
    implements $ImageFilter_BlurCopyWith<$Res> {
  _$ImageFilter_BlurCopyWithImpl(this._self, this._then);

  final ImageFilter_Blur _self;
  final $Res Function(ImageFilter_Blur) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? radius = null,}) {
  return _then(ImageFilter_Blur(
radius: null == radius ? _self.radius : radius // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ImageFilter_Sharpen extends ImageFilter {
  const ImageFilter_Sharpen(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_Sharpen);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ImageFilter.sharpen()';
}


}




/// @nodoc


class ImageFilter_Brightness extends ImageFilter {
  const ImageFilter_Brightness({required this.amount}): super._();
  

 final  int amount;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_BrightnessCopyWith<ImageFilter_Brightness> get copyWith => _$ImageFilter_BrightnessCopyWithImpl<ImageFilter_Brightness>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_Brightness&&(identical(other.amount, amount) || other.amount == amount));
}


@override
int get hashCode => Object.hash(runtimeType,amount);

@override
String toString() {
  return 'ImageFilter.brightness(amount: $amount)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_BrightnessCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_BrightnessCopyWith(ImageFilter_Brightness value, $Res Function(ImageFilter_Brightness) _then) = _$ImageFilter_BrightnessCopyWithImpl;
@useResult
$Res call({
 int amount
});




}
/// @nodoc
class _$ImageFilter_BrightnessCopyWithImpl<$Res>
    implements $ImageFilter_BrightnessCopyWith<$Res> {
  _$ImageFilter_BrightnessCopyWithImpl(this._self, this._then);

  final ImageFilter_Brightness _self;
  final $Res Function(ImageFilter_Brightness) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? amount = null,}) {
  return _then(ImageFilter_Brightness(
amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ImageFilter_Contrast extends ImageFilter {
  const ImageFilter_Contrast({required this.amount}): super._();
  

 final  double amount;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_ContrastCopyWith<ImageFilter_Contrast> get copyWith => _$ImageFilter_ContrastCopyWithImpl<ImageFilter_Contrast>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_Contrast&&(identical(other.amount, amount) || other.amount == amount));
}


@override
int get hashCode => Object.hash(runtimeType,amount);

@override
String toString() {
  return 'ImageFilter.contrast(amount: $amount)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_ContrastCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_ContrastCopyWith(ImageFilter_Contrast value, $Res Function(ImageFilter_Contrast) _then) = _$ImageFilter_ContrastCopyWithImpl;
@useResult
$Res call({
 double amount
});




}
/// @nodoc
class _$ImageFilter_ContrastCopyWithImpl<$Res>
    implements $ImageFilter_ContrastCopyWith<$Res> {
  _$ImageFilter_ContrastCopyWithImpl(this._self, this._then);

  final ImageFilter_Contrast _self;
  final $Res Function(ImageFilter_Contrast) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? amount = null,}) {
  return _then(ImageFilter_Contrast(
amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class ImageFilter_Saturation extends ImageFilter {
  const ImageFilter_Saturation({required this.amount}): super._();
  

 final  double amount;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_SaturationCopyWith<ImageFilter_Saturation> get copyWith => _$ImageFilter_SaturationCopyWithImpl<ImageFilter_Saturation>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_Saturation&&(identical(other.amount, amount) || other.amount == amount));
}


@override
int get hashCode => Object.hash(runtimeType,amount);

@override
String toString() {
  return 'ImageFilter.saturation(amount: $amount)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_SaturationCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_SaturationCopyWith(ImageFilter_Saturation value, $Res Function(ImageFilter_Saturation) _then) = _$ImageFilter_SaturationCopyWithImpl;
@useResult
$Res call({
 double amount
});




}
/// @nodoc
class _$ImageFilter_SaturationCopyWithImpl<$Res>
    implements $ImageFilter_SaturationCopyWith<$Res> {
  _$ImageFilter_SaturationCopyWithImpl(this._self, this._then);

  final ImageFilter_Saturation _self;
  final $Res Function(ImageFilter_Saturation) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? amount = null,}) {
  return _then(ImageFilter_Saturation(
amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class ImageFilter_HueRotate extends ImageFilter {
  const ImageFilter_HueRotate({required this.degrees}): super._();
  

 final  double degrees;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_HueRotateCopyWith<ImageFilter_HueRotate> get copyWith => _$ImageFilter_HueRotateCopyWithImpl<ImageFilter_HueRotate>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_HueRotate&&(identical(other.degrees, degrees) || other.degrees == degrees));
}


@override
int get hashCode => Object.hash(runtimeType,degrees);

@override
String toString() {
  return 'ImageFilter.hueRotate(degrees: $degrees)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_HueRotateCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_HueRotateCopyWith(ImageFilter_HueRotate value, $Res Function(ImageFilter_HueRotate) _then) = _$ImageFilter_HueRotateCopyWithImpl;
@useResult
$Res call({
 double degrees
});




}
/// @nodoc
class _$ImageFilter_HueRotateCopyWithImpl<$Res>
    implements $ImageFilter_HueRotateCopyWith<$Res> {
  _$ImageFilter_HueRotateCopyWithImpl(this._self, this._then);

  final ImageFilter_HueRotate _self;
  final $Res Function(ImageFilter_HueRotate) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? degrees = null,}) {
  return _then(ImageFilter_HueRotate(
degrees: null == degrees ? _self.degrees : degrees // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class ImageFilter_Oil extends ImageFilter {
  const ImageFilter_Oil({required this.radius, required this.intensity}): super._();
  

 final  int radius;
 final  double intensity;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_OilCopyWith<ImageFilter_Oil> get copyWith => _$ImageFilter_OilCopyWithImpl<ImageFilter_Oil>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_Oil&&(identical(other.radius, radius) || other.radius == radius)&&(identical(other.intensity, intensity) || other.intensity == intensity));
}


@override
int get hashCode => Object.hash(runtimeType,radius,intensity);

@override
String toString() {
  return 'ImageFilter.oil(radius: $radius, intensity: $intensity)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_OilCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_OilCopyWith(ImageFilter_Oil value, $Res Function(ImageFilter_Oil) _then) = _$ImageFilter_OilCopyWithImpl;
@useResult
$Res call({
 int radius, double intensity
});




}
/// @nodoc
class _$ImageFilter_OilCopyWithImpl<$Res>
    implements $ImageFilter_OilCopyWith<$Res> {
  _$ImageFilter_OilCopyWithImpl(this._self, this._then);

  final ImageFilter_Oil _self;
  final $Res Function(ImageFilter_Oil) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? radius = null,Object? intensity = null,}) {
  return _then(ImageFilter_Oil(
radius: null == radius ? _self.radius : radius // ignore: cast_nullable_to_non_nullable
as int,intensity: null == intensity ? _self.intensity : intensity // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class ImageFilter_FrostedGlass extends ImageFilter {
  const ImageFilter_FrostedGlass(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_FrostedGlass);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ImageFilter.frostedGlass()';
}


}




/// @nodoc


class ImageFilter_Pixelize extends ImageFilter {
  const ImageFilter_Pixelize({required this.size}): super._();
  

 final  int size;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_PixelizeCopyWith<ImageFilter_Pixelize> get copyWith => _$ImageFilter_PixelizeCopyWithImpl<ImageFilter_Pixelize>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_Pixelize&&(identical(other.size, size) || other.size == size));
}


@override
int get hashCode => Object.hash(runtimeType,size);

@override
String toString() {
  return 'ImageFilter.pixelize(size: $size)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_PixelizeCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_PixelizeCopyWith(ImageFilter_Pixelize value, $Res Function(ImageFilter_Pixelize) _then) = _$ImageFilter_PixelizeCopyWithImpl;
@useResult
$Res call({
 int size
});




}
/// @nodoc
class _$ImageFilter_PixelizeCopyWithImpl<$Res>
    implements $ImageFilter_PixelizeCopyWith<$Res> {
  _$ImageFilter_PixelizeCopyWithImpl(this._self, this._then);

  final ImageFilter_Pixelize _self;
  final $Res Function(ImageFilter_Pixelize) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? size = null,}) {
  return _then(ImageFilter_Pixelize(
size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ImageFilter_Solarize extends ImageFilter {
  const ImageFilter_Solarize(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_Solarize);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ImageFilter.solarize()';
}


}




/// @nodoc


class ImageFilter_Preset extends ImageFilter {
  const ImageFilter_Preset({required this.preset, required this.strength}): super._();
  

 final  FilterPreset preset;
 final  double strength;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_PresetCopyWith<ImageFilter_Preset> get copyWith => _$ImageFilter_PresetCopyWithImpl<ImageFilter_Preset>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_Preset&&(identical(other.preset, preset) || other.preset == preset)&&(identical(other.strength, strength) || other.strength == strength));
}


@override
int get hashCode => Object.hash(runtimeType,preset,strength);

@override
String toString() {
  return 'ImageFilter.preset(preset: $preset, strength: $strength)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_PresetCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_PresetCopyWith(ImageFilter_Preset value, $Res Function(ImageFilter_Preset) _then) = _$ImageFilter_PresetCopyWithImpl;
@useResult
$Res call({
 FilterPreset preset, double strength
});




}
/// @nodoc
class _$ImageFilter_PresetCopyWithImpl<$Res>
    implements $ImageFilter_PresetCopyWith<$Res> {
  _$ImageFilter_PresetCopyWithImpl(this._self, this._then);

  final ImageFilter_Preset _self;
  final $Res Function(ImageFilter_Preset) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? preset = null,Object? strength = null,}) {
  return _then(ImageFilter_Preset(
preset: null == preset ? _self.preset : preset // ignore: cast_nullable_to_non_nullable
as FilterPreset,strength: null == strength ? _self.strength : strength // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class ImageFilter_Warmth extends ImageFilter {
  const ImageFilter_Warmth({required this.amount}): super._();
  

 final  double amount;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_WarmthCopyWith<ImageFilter_Warmth> get copyWith => _$ImageFilter_WarmthCopyWithImpl<ImageFilter_Warmth>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_Warmth&&(identical(other.amount, amount) || other.amount == amount));
}


@override
int get hashCode => Object.hash(runtimeType,amount);

@override
String toString() {
  return 'ImageFilter.warmth(amount: $amount)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_WarmthCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_WarmthCopyWith(ImageFilter_Warmth value, $Res Function(ImageFilter_Warmth) _then) = _$ImageFilter_WarmthCopyWithImpl;
@useResult
$Res call({
 double amount
});




}
/// @nodoc
class _$ImageFilter_WarmthCopyWithImpl<$Res>
    implements $ImageFilter_WarmthCopyWith<$Res> {
  _$ImageFilter_WarmthCopyWithImpl(this._self, this._then);

  final ImageFilter_Warmth _self;
  final $Res Function(ImageFilter_Warmth) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? amount = null,}) {
  return _then(ImageFilter_Warmth(
amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class ImageFilter_Fade extends ImageFilter {
  const ImageFilter_Fade({required this.amount}): super._();
  

 final  double amount;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_FadeCopyWith<ImageFilter_Fade> get copyWith => _$ImageFilter_FadeCopyWithImpl<ImageFilter_Fade>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_Fade&&(identical(other.amount, amount) || other.amount == amount));
}


@override
int get hashCode => Object.hash(runtimeType,amount);

@override
String toString() {
  return 'ImageFilter.fade(amount: $amount)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_FadeCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_FadeCopyWith(ImageFilter_Fade value, $Res Function(ImageFilter_Fade) _then) = _$ImageFilter_FadeCopyWithImpl;
@useResult
$Res call({
 double amount
});




}
/// @nodoc
class _$ImageFilter_FadeCopyWithImpl<$Res>
    implements $ImageFilter_FadeCopyWith<$Res> {
  _$ImageFilter_FadeCopyWithImpl(this._self, this._then);

  final ImageFilter_Fade _self;
  final $Res Function(ImageFilter_Fade) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? amount = null,}) {
  return _then(ImageFilter_Fade(
amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class ImageFilter_Vignette extends ImageFilter {
  const ImageFilter_Vignette({required this.amount}): super._();
  

 final  double amount;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_VignetteCopyWith<ImageFilter_Vignette> get copyWith => _$ImageFilter_VignetteCopyWithImpl<ImageFilter_Vignette>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_Vignette&&(identical(other.amount, amount) || other.amount == amount));
}


@override
int get hashCode => Object.hash(runtimeType,amount);

@override
String toString() {
  return 'ImageFilter.vignette(amount: $amount)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_VignetteCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_VignetteCopyWith(ImageFilter_Vignette value, $Res Function(ImageFilter_Vignette) _then) = _$ImageFilter_VignetteCopyWithImpl;
@useResult
$Res call({
 double amount
});




}
/// @nodoc
class _$ImageFilter_VignetteCopyWithImpl<$Res>
    implements $ImageFilter_VignetteCopyWith<$Res> {
  _$ImageFilter_VignetteCopyWithImpl(this._self, this._then);

  final ImageFilter_Vignette _self;
  final $Res Function(ImageFilter_Vignette) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? amount = null,}) {
  return _then(ImageFilter_Vignette(
amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class ImageFilter_Highlights extends ImageFilter {
  const ImageFilter_Highlights({required this.amount}): super._();
  

 final  double amount;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_HighlightsCopyWith<ImageFilter_Highlights> get copyWith => _$ImageFilter_HighlightsCopyWithImpl<ImageFilter_Highlights>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_Highlights&&(identical(other.amount, amount) || other.amount == amount));
}


@override
int get hashCode => Object.hash(runtimeType,amount);

@override
String toString() {
  return 'ImageFilter.highlights(amount: $amount)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_HighlightsCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_HighlightsCopyWith(ImageFilter_Highlights value, $Res Function(ImageFilter_Highlights) _then) = _$ImageFilter_HighlightsCopyWithImpl;
@useResult
$Res call({
 double amount
});




}
/// @nodoc
class _$ImageFilter_HighlightsCopyWithImpl<$Res>
    implements $ImageFilter_HighlightsCopyWith<$Res> {
  _$ImageFilter_HighlightsCopyWithImpl(this._self, this._then);

  final ImageFilter_Highlights _self;
  final $Res Function(ImageFilter_Highlights) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? amount = null,}) {
  return _then(ImageFilter_Highlights(
amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class ImageFilter_Shadows extends ImageFilter {
  const ImageFilter_Shadows({required this.amount}): super._();
  

 final  double amount;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_ShadowsCopyWith<ImageFilter_Shadows> get copyWith => _$ImageFilter_ShadowsCopyWithImpl<ImageFilter_Shadows>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_Shadows&&(identical(other.amount, amount) || other.amount == amount));
}


@override
int get hashCode => Object.hash(runtimeType,amount);

@override
String toString() {
  return 'ImageFilter.shadows(amount: $amount)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_ShadowsCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_ShadowsCopyWith(ImageFilter_Shadows value, $Res Function(ImageFilter_Shadows) _then) = _$ImageFilter_ShadowsCopyWithImpl;
@useResult
$Res call({
 double amount
});




}
/// @nodoc
class _$ImageFilter_ShadowsCopyWithImpl<$Res>
    implements $ImageFilter_ShadowsCopyWith<$Res> {
  _$ImageFilter_ShadowsCopyWithImpl(this._self, this._then);

  final ImageFilter_Shadows _self;
  final $Res Function(ImageFilter_Shadows) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? amount = null,}) {
  return _then(ImageFilter_Shadows(
amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class ImageFilter_Structure extends ImageFilter {
  const ImageFilter_Structure({required this.amount}): super._();
  

 final  double amount;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_StructureCopyWith<ImageFilter_Structure> get copyWith => _$ImageFilter_StructureCopyWithImpl<ImageFilter_Structure>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_Structure&&(identical(other.amount, amount) || other.amount == amount));
}


@override
int get hashCode => Object.hash(runtimeType,amount);

@override
String toString() {
  return 'ImageFilter.structure(amount: $amount)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_StructureCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_StructureCopyWith(ImageFilter_Structure value, $Res Function(ImageFilter_Structure) _then) = _$ImageFilter_StructureCopyWithImpl;
@useResult
$Res call({
 double amount
});




}
/// @nodoc
class _$ImageFilter_StructureCopyWithImpl<$Res>
    implements $ImageFilter_StructureCopyWith<$Res> {
  _$ImageFilter_StructureCopyWithImpl(this._self, this._then);

  final ImageFilter_Structure _self;
  final $Res Function(ImageFilter_Structure) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? amount = null,}) {
  return _then(ImageFilter_Structure(
amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class ImageFilter_Mood extends ImageFilter {
  const ImageFilter_Mood({required this.preset, required this.strength}): super._();
  

 final  MoodFilterPreset preset;
 final  double strength;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_MoodCopyWith<ImageFilter_Mood> get copyWith => _$ImageFilter_MoodCopyWithImpl<ImageFilter_Mood>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_Mood&&(identical(other.preset, preset) || other.preset == preset)&&(identical(other.strength, strength) || other.strength == strength));
}


@override
int get hashCode => Object.hash(runtimeType,preset,strength);

@override
String toString() {
  return 'ImageFilter.mood(preset: $preset, strength: $strength)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_MoodCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_MoodCopyWith(ImageFilter_Mood value, $Res Function(ImageFilter_Mood) _then) = _$ImageFilter_MoodCopyWithImpl;
@useResult
$Res call({
 MoodFilterPreset preset, double strength
});




}
/// @nodoc
class _$ImageFilter_MoodCopyWithImpl<$Res>
    implements $ImageFilter_MoodCopyWith<$Res> {
  _$ImageFilter_MoodCopyWithImpl(this._self, this._then);

  final ImageFilter_Mood _self;
  final $Res Function(ImageFilter_Mood) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? preset = null,Object? strength = null,}) {
  return _then(ImageFilter_Mood(
preset: null == preset ? _self.preset : preset // ignore: cast_nullable_to_non_nullable
as MoodFilterPreset,strength: null == strength ? _self.strength : strength // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class ImageFilter_SwipeLook extends ImageFilter {
  const ImageFilter_SwipeLook({required this.preset, required this.strength}): super._();
  

 final  SwipeLookPreset preset;
 final  double strength;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_SwipeLookCopyWith<ImageFilter_SwipeLook> get copyWith => _$ImageFilter_SwipeLookCopyWithImpl<ImageFilter_SwipeLook>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_SwipeLook&&(identical(other.preset, preset) || other.preset == preset)&&(identical(other.strength, strength) || other.strength == strength));
}


@override
int get hashCode => Object.hash(runtimeType,preset,strength);

@override
String toString() {
  return 'ImageFilter.swipeLook(preset: $preset, strength: $strength)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_SwipeLookCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_SwipeLookCopyWith(ImageFilter_SwipeLook value, $Res Function(ImageFilter_SwipeLook) _then) = _$ImageFilter_SwipeLookCopyWithImpl;
@useResult
$Res call({
 SwipeLookPreset preset, double strength
});




}
/// @nodoc
class _$ImageFilter_SwipeLookCopyWithImpl<$Res>
    implements $ImageFilter_SwipeLookCopyWith<$Res> {
  _$ImageFilter_SwipeLookCopyWithImpl(this._self, this._then);

  final ImageFilter_SwipeLook _self;
  final $Res Function(ImageFilter_SwipeLook) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? preset = null,Object? strength = null,}) {
  return _then(ImageFilter_SwipeLook(
preset: null == preset ? _self.preset : preset // ignore: cast_nullable_to_non_nullable
as SwipeLookPreset,strength: null == strength ? _self.strength : strength // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class ImageFilter_LutPng extends ImageFilter {
  const ImageFilter_LutPng({required this.pngBytes, required this.strength}): super._();
  

 final  Uint8List pngBytes;
 final  double strength;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_LutPngCopyWith<ImageFilter_LutPng> get copyWith => _$ImageFilter_LutPngCopyWithImpl<ImageFilter_LutPng>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_LutPng&&const DeepCollectionEquality().equals(other.pngBytes, pngBytes)&&(identical(other.strength, strength) || other.strength == strength));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(pngBytes),strength);

@override
String toString() {
  return 'ImageFilter.lutPng(pngBytes: $pngBytes, strength: $strength)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_LutPngCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_LutPngCopyWith(ImageFilter_LutPng value, $Res Function(ImageFilter_LutPng) _then) = _$ImageFilter_LutPngCopyWithImpl;
@useResult
$Res call({
 Uint8List pngBytes, double strength
});




}
/// @nodoc
class _$ImageFilter_LutPngCopyWithImpl<$Res>
    implements $ImageFilter_LutPngCopyWith<$Res> {
  _$ImageFilter_LutPngCopyWithImpl(this._self, this._then);

  final ImageFilter_LutPng _self;
  final $Res Function(ImageFilter_LutPng) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? pngBytes = null,Object? strength = null,}) {
  return _then(ImageFilter_LutPng(
pngBytes: null == pngBytes ? _self.pngBytes : pngBytes // ignore: cast_nullable_to_non_nullable
as Uint8List,strength: null == strength ? _self.strength : strength // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class ImageFilter_SkinSmooth extends ImageFilter {
  const ImageFilter_SkinSmooth({required this.strength}): super._();
  

 final  double strength;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_SkinSmoothCopyWith<ImageFilter_SkinSmooth> get copyWith => _$ImageFilter_SkinSmoothCopyWithImpl<ImageFilter_SkinSmooth>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_SkinSmooth&&(identical(other.strength, strength) || other.strength == strength));
}


@override
int get hashCode => Object.hash(runtimeType,strength);

@override
String toString() {
  return 'ImageFilter.skinSmooth(strength: $strength)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_SkinSmoothCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_SkinSmoothCopyWith(ImageFilter_SkinSmooth value, $Res Function(ImageFilter_SkinSmooth) _then) = _$ImageFilter_SkinSmoothCopyWithImpl;
@useResult
$Res call({
 double strength
});




}
/// @nodoc
class _$ImageFilter_SkinSmoothCopyWithImpl<$Res>
    implements $ImageFilter_SkinSmoothCopyWith<$Res> {
  _$ImageFilter_SkinSmoothCopyWithImpl(this._self, this._then);

  final ImageFilter_SkinSmooth _self;
  final $Res Function(ImageFilter_SkinSmooth) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? strength = null,}) {
  return _then(ImageFilter_SkinSmooth(
strength: null == strength ? _self.strength : strength // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class ImageFilter_Beauty extends ImageFilter {
  const ImageFilter_Beauty({required this.params}): super._();
  

 final  BeautyParams params;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageFilter_BeautyCopyWith<ImageFilter_Beauty> get copyWith => _$ImageFilter_BeautyCopyWithImpl<ImageFilter_Beauty>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageFilter_Beauty&&(identical(other.params, params) || other.params == params));
}


@override
int get hashCode => Object.hash(runtimeType,params);

@override
String toString() {
  return 'ImageFilter.beauty(params: $params)';
}


}

/// @nodoc
abstract mixin class $ImageFilter_BeautyCopyWith<$Res> implements $ImageFilterCopyWith<$Res> {
  factory $ImageFilter_BeautyCopyWith(ImageFilter_Beauty value, $Res Function(ImageFilter_Beauty) _then) = _$ImageFilter_BeautyCopyWithImpl;
@useResult
$Res call({
 BeautyParams params
});




}
/// @nodoc
class _$ImageFilter_BeautyCopyWithImpl<$Res>
    implements $ImageFilter_BeautyCopyWith<$Res> {
  _$ImageFilter_BeautyCopyWithImpl(this._self, this._then);

  final ImageFilter_Beauty _self;
  final $Res Function(ImageFilter_Beauty) _then;

/// Create a copy of ImageFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? params = null,}) {
  return _then(ImageFilter_Beauty(
params: null == params ? _self.params : params // ignore: cast_nullable_to_non_nullable
as BeautyParams,
  ));
}


}

// dart format on
