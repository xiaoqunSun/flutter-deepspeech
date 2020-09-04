 cp ../today_is_different.scorer ../deepspeech-0.8.0-models.tflite app/src/main/assets
 ./gradlew :app:assembleRelease
 adb install -r ../build/app/outputs/apk/release/app-release.apk
