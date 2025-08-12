# Keep all ExoPlayer classes
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# Keep all just_audio classes
-keep class com.ryanheise.just_audio.** { *; }
-dontwarn com.ryanheise.just_audio.**

# Keep flutter plugins
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.plugins.**
