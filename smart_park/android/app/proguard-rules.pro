# Release builds shrink the code with R8.
#
# google_mlkit_text_recognition can load every ML Kit script, but SmartPark
# only reads plates in Latin script and does not bundle the others. Without
# these lines R8 stops on the missing classes.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
