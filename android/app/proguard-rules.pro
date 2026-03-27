# Flutter ProGuard Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep entire app package (critical — prevents class stripping of MainActivity etc.)
-keep class com.jarvis.jarvis_ai.** { *; }

# Hive local database — MUST keep or app crashes
-keep class com.hive.** { *; }
-keep class dev.flutter.** { *; }

# Google ML Kit
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.** { *; }

# Flutter secure storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# File picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Syncfusion PDF
-keep class com.syncfusion.flutter.** { *; }

# Speech to text
-keep class com.csdcorp.speech_to_text.** { *; }

# Flutter TTS
-keep class com.tundralabs.fluttertts.** { *; }

# Kotlin coroutines & reflection (required for Kotlin classes in R8)
-keep class kotlin.Metadata { *; }
-keep class kotlin.reflect.** { *; }
-keepclassmembers class kotlin.Lazy { *; }
-dontwarn kotlin.**

# Gson / JSON serialization (used by Hive adapters)
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }

# OkHttp (used by http/dio packages)
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

# AndroidX
-keep class androidx.** { *; }
-keep interface androidx.** { *; }

# Missing warns — suppress safe
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.android.play.core.**
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

# Keep HiveObject adapters (auto-generated, critical for local storage)
-keep class * extends com.hive.adapters.TypeAdapter { *; }
-keepclassmembers class * {
    @com.hive.annotations.HiveField *;
}
