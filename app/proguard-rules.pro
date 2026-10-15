# NOVA AI ProGuard / R8 rules.
# Keep line numbers so release crash logs stay readable.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Keep the app's own classes needed by the system (Application, Activities).
-keep class com.nova.ai.NovaApp { *; }
-keep class com.nova.ai.MainActivity { *; }
