Universal Music Player sample  for Ceylon on Android
====================================================

This sample shows how to implement an audio media app that works
across multiple form factors and provide a consistent user experience
on Android phones, tablets, Android Auto, Android Wear, Android TV and
Google Cast devices.


Introduction
------------

This is a [Universal Music Player][1] sample application for Android,
partially ported to [Ceylon](https://ceylon-lang.org).

It demonstrates how to implement an audio media app that works
across multiple form factors and provide a consistent user experience
on Android phones, tablets, Android Auto, Android Wear, Android TV and
Google Cast devices.

It also demonstrates how to have an Android project containing a mix of
Ceylon code alongside Java code, using the [Ceylon Gradle plugin for Android][2].
(We've deliberately left some of the original Java code alone, in order to
demonstrate this.)

[1]: https://github.com/googlesamples/android-UniversalMusicPlayer
[2]: https://github.com/ceylon/ceylon-gradle-android

Pre-requisites
--------------

- Ceylon 1.3.2
- Android SDK v17

Getting Started
---------------

This sample uses the Gradle build system. To build this project, use the
`gradlew build` command or use 'Import Project' in Android Studio.

Screenshots
-----------

![Phone](screenshots/phone.png "On a phone")
![Lock screen](screenshots/phone_lockscreen.png "Lockscreen background and controls")
![Full screen player](screenshots/phone_fullscreen_player.png "A basic full screen activity")
![Cast dialog](screenshots/phone_cast_dialog.png "Casting to Google Cast devices")
![Android Auto](screenshots/android_auto.png "Running on an Android Auto car")
![Android TV](screenshots/android_tv.png "Running on an Android TV")

![Android Wear watch face](screenshots/android_wear_1.png "MediaStyle notifications on an Android Wear watch")
![Android Wear controls](screenshots/android_wear_2.png "Media playback controls on an Android Wear watch")
