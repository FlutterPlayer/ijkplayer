#!/bin/sh

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
cd "$REPO_DIR"
set -e

VERSION_CODE=800800
VERSION_NAME=0.8.8
VERSION_TARGET=$1

do_version_readme() {
    # README.md
    # cat README.md \
    # | sed "s/\(#compile 'tv.danmaku.ijk.media:ijkplayer-java:#\)[[:digit:]][[:digit:].]*\(#'#\)/\1:$VERSION_NAME\2/" \
    # > README.md.new

    cat README.md \
    | sed "s/\(compile \'tv.danmaku.ijk.media:ijkplayer-[[:alnum:]_]*:\)[[:digit:].]*[[:digit:]]/\1$VERSION_NAME/g" \
    | sed "s/\(git checkout -B latest k\)[[:digit:]][[:digit:].]*/\1$VERSION_NAME/g" \
    > README.md.new

    mv -f README.md.new README.md
}

do_version_gradle() {
    # platform/android/ijkplayer/build.gradle
    cat platform/android/ijkplayer/build.gradle \
    | sed "s/\(versionCode[[:space:]]*=[[:space:]]*\)[[:digit:]][[:digit:]]*/\1$VERSION_CODE/" \
    | sed "s/\(versionName[[:space:]]*=[[:space:]]*\)\"[[:digit:].]*[[:digit:]]\"/\1\"$VERSION_NAME\"/" \
    > platform/android/ijkplayer/build.gradle.new

    mv -f platform/android/ijkplayer/build.gradle.new platform/android/ijkplayer/build.gradle



    # platform/android/ijkplayer/gradle.properties
    cat platform/android/ijkplayer/gradle.properties \
    | sed "s/\(VERSION_NAME=\)[[:digit:].]*[[:digit:]]/\1$VERSION_NAME/" \
    | sed "s/\(VERSION_CODE=\)[[:digit:]][[:digit:]]*/\1$VERSION_CODE/" \
    > platform/android/ijkplayer/gradle.properties.new

    mv -f platform/android/ijkplayer/gradle.properties.new platform/android/ijkplayer/gradle.properties



    # platform/android/ijkplayer/ijkplayer-example/build.gradle
    cat platform/android/ijkplayer/ijkplayer-example/build.gradle \
    | sed "s/\(ompile \'tv.danmaku.ijk.media:ijkplayer-[-_[:alpha:][:digit:]]*:\)[[:digit:].]*[[:digit:]]/\1$VERSION_NAME/g" \
    > platform/android/ijkplayer/ijkplayer-example/build.gradle.new

    mv -f platform/android/ijkplayer/ijkplayer-example/build.gradle.new platform/android/ijkplayer/ijkplayer-example/build.gradle
}

do_version_xcode() {
    # platform/ios/IJKMediaPlayer/IJKMediaPlayer.xcodeproj/project.pbxproj

    cat platform/ios/IJKMediaPlayer/IJKMediaPlayer.xcodeproj/project.pbxproj \
    | sed "s/\(CURRENT_PROJECT_VERSION = \).*;/\1$VERSION_NAME;/g" \
    > platform/ios/IJKMediaPlayer/IJKMediaPlayer.xcodeproj/project.pbxproj.new

    mv -f platform/ios/IJKMediaPlayer/IJKMediaPlayer.xcodeproj/project.pbxproj.new platform/ios/IJKMediaPlayer/IJKMediaPlayer.xcodeproj/project.pbxproj
}

if [ "$VERSION_TARGET" = "readme" ]; then
    do_version_readme
elif [ "$VERSION_TARGET" = "gradle" ]; then
    do_version_gradle
elif [ "$VERSION_TARGET" = "show" ]; then
    echo $VERSION_NAME
elif [ "$VERSION_TARGET" = "xcode" ]; then
    do_version_xcode
else
    do_version_readme
    do_version_gradle
    do_version_xcode
fi

