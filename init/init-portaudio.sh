#! /usr/bin/env bash
#
# Copyright (C) 2013-2015 Bilibili
# Copyright (C) 2013-2015 Zhang Rui <bbcallen@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASEDIR=$(dirname "$DIR")

PORTAUDIO_UPSTREAM=https://github.com/PortAudio/portaudio.git
PORTAUDIO_FORK=https://github.com/PortAudio/portaudio.git
PORTAUDIO_COMMIT=147dd722548358763a8b649b3e4b41dfffbcfbb6
PORTAUDIO_LOCAL_REPO=$BASEDIR/extra/portaudio

set -e
TOOLS=$BASEDIR/tools

echo "== pull portaudio base =="
sh $TOOLS/pull-repo-base.sh $PORTAUDIO_UPSTREAM $PORTAUDIO_LOCAL_REPO

echo "== pull portaudio fork =="
sh $TOOLS/pull-repo-ref.sh $PORTAUDIO_FORK $BASEDIR/ijkmedia/portaudio ${PORTAUDIO_LOCAL_REPO}
cd $BASEDIR/ijkmedia/portaudio
git checkout ${PORTAUDIO_COMMIT} -B ijkplayer
cd -
