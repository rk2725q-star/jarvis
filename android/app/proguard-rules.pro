# ─────────────────────────────────────────────────────────────────────────────
# Flutter core — mandatory
# ─────────────────────────────────────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.** { *; }

# App-specific entry points
-keep class com.jarvis.jarvis_ai.** { *; }
-keep class dev.flutter.** { *; }

# ─────────────────────────────────────────────────────────────────────────────
# Kotlin — keep metadata for reflection, dontwarn for internals
# ─────────────────────────────────────────────────────────────────────────────
-keep class kotlin.Metadata { *; }
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable
-dontwarn kotlin.**
-dontwarn kotlinx.**

# ─────────────────────────────────────────────────────────────────────────────
# Serialization / JSON
# ─────────────────────────────────────────────────────────────────────────────
-keep class com.google.gson.** { *; }
-dontwarn sun.misc.**

# ─────────────────────────────────────────────────────────────────────────────
# OkHttp / Dio networking
# ─────────────────────────────────────────────────────────────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.internal.** { *; }
-keep interface okhttp3.** { *; }

# ─────────────────────────────────────────────────────────────────────────────
# Google ML Kit (text recognition)
# ─────────────────────────────────────────────────────────────────────────────
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.common.** { *; }
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**

# ─────────────────────────────────────────────────────────────────────────────
# Flutter plugin packages — keep plugin registry entries
# ─────────────────────────────────────────────────────────────────────────────
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class com.syncfusion.flutter.** { *; }
-keep class com.csdcorp.speech_to_text.** { *; }
-keep class com.tundralabs.fluttertts.** { *; }
-keep class com.hive.** { *; }

# ExoPlayer (video_player, just_audio)
-keep class com.google.android.exoplayer2.** { *; }
-keep interface com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# Audio service / media session
-keep class androidx.media.** { *; }
-keep class android.support.v4.media.** { *; }

# ─────────────────────────────────────────────────────────────────────────────
# Hive local database
# ─────────────────────────────────────────────────────────────────────────────
-keep class * extends com.hive.adapters.TypeAdapter { *; }
-keepclassmembers class * {
    @com.hive.annotations.HiveField *;
}

# ─────────────────────────────────────────────────────────────────────────────
# General Android / Play Core / Bouncycastle
# ─────────────────────────────────────────────────────────────────────────────
-dontwarn com.google.android.play.core.**
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
-dontwarn javax.annotation.**
-dontwarn javax.lang.model.**

# ─────────────────────────────────────────────────────────────────────────────
# R8 / optimization tuning
# ─────────────────────────────────────────────────────────────────────────────
# Allow R8 to aggressively optimize method arguments
-optimizationpasses 5
-allowaccessmodification
-mergeinterfacesaggressively

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Parcelable implementations (used by Android platform)
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
