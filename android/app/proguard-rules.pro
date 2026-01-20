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

