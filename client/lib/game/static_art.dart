import 'dart:ui';

/// Records [draw] once into a replayable display list.
///
/// This is the whole static-art pipeline, and it is the decision that makes
/// Phase 9 affordable.
///
/// Before it, the floor and furniture components rebuilt every rect,
/// every grid line and every label **on every frame**. At ~40 draw ops of flat
/// colour that was free. Plank floors, carpet weave, tile checker, prop
/// shadows and a stepped deck are not 40 ops, they are several hundred, and
/// several hundred ops sixty times a second on a mid-range Android phone is a
/// slideshow. Recording them once turns rich static detail into a **load-time**
/// cost instead of a per-frame one: replaying a 500-op display list costs the
/// same per frame as replaying a 1-op one, because the work already happened.
///
/// **`drawPicture`, deliberately not `Picture.toImage`.** Rasterising the
/// 1600x1200 world at a supersample large enough to survive a camera zoom of
/// 1.6 is roughly 30 MB of VRAM, and rasterising it at 1:1 goes visibly soft
/// the moment the camera zooms in — which it always is. A display list stays
/// vector, stays crisp at any zoom, and Skia culls the ops that fall outside
/// the clip for free.
///
/// If profiling ever says one picture is too much, the fallback is **one
/// picture per zone**, replaying only the zones that intersect the camera
/// rect. It is not rasterisation, and it is not cutting the art.
///
/// Anything that *moves* — water, splashes, the crowd glow, string lights —
/// stays outside the picture and keeps drawing live. A display list is a
/// recording; putting an animation in one just freezes the first frame of it.
Picture recordPicture(void Function(Canvas canvas) draw) {
  final recorder = PictureRecorder();
  draw(Canvas(recorder));
  return recorder.endRecording();
}
