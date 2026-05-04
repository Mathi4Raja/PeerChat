# Flutter ProGuard Rules

# Keep Flutter classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep classes used by reflection
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod

# Sodium specific (if needed)
-keep class com.goterl.lazy_sodium.** { *; }

# SQLite specific
-keep class net.sqlcipher.** { *; }
-keep class org.sqlite.** { *; }

# Google Play Services / Play Core / Firebase
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# Keep standard library classes
-dontwarn java.lang.invoke.**
-dontwarn javax.annotation.**
-dontwarn sun.misc.Unsafe
-dontwarn com.google.j2objc.annotations.**
-dontwarn com.google.errorprone.annotations.**
