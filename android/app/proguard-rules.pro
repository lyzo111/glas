# ML Kit finds its parts by reflection; without these R8 strips them and the depth effect's
# segmenter comes up empty.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-keep class com.google.firebase.components.** { *; }
