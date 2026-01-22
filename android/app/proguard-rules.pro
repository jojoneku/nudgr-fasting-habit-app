# Flutter Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# Keep standard Android classes used for Notifications
-keep class androidx.core.app.** { *; }
-keep class android.support.v4.app.** { *; }

# Keep resources logic
-keep class **.R$* {
    <fields>;
}

# Timezone data might utilize reflection or specific resource loading
-keep class org.threeten.bp.** { *; }
-keep class kotlinx.datetime.** { *; }

# Gson Configuration (CRITICAL for flutter_local_notifications in release mode)
# Fixes: java.lang.RuntimeException: Missing type parameter
-keepattributes Signature
-keepattributes *Annotation*
-keep class sun.misc.Unsafe { *; }
-keep class com.google.gson.** { *; }

# Fix for TypeToken generic type parameters being stripped
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

