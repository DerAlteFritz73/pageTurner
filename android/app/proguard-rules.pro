# Gson serialization
-keepattributes Signature
-keepattributes *Annotation*

# Keep Gson SerializedName annotations
-keep class com.google.gson.annotations.SerializedName

# Keep flutter_presentation_display DisplayModel fields
-keep class com.elriztechnology.flutter_presentation_display.DisplayModel { *; }
