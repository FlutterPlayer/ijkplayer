#
# Copyright (c) 2019 Befovy <befovy@gmail.com>
#
# This file is part of fijkPlayer.
#
# fijkPlayer is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# fijkPlayer is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with ijkPlayer; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
#

cmake_minimum_required(VERSION 3.5)

if (NOT DEFINED FIJKROOT_PATH)
    set(FIJKROOT_PATH ${CMAKE_CURRENT_LIST_DIR}/../)
endif ()

if (NOT WIN32)
    add_compile_options("-Wno-implicit-const-int-float-conversion")
endif ()

add_subdirectory(ijksdl)
add_subdirectory(ijkplayer)

set(GIT_DESCRIBE "unknown, dose not found git")
execute_process(
        COMMAND git describe --dirty
        OUTPUT_VARIABLE GIT_DESCRIBE
        OUTPUT_STRIP_TRAILING_WHITESPACE
        # ERROR_QUIET
        WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
)
configure_file(ijkplayer/ijkversion.h.in ${CMAKE_CURRENT_LIST_DIR}/ijkplayer/ijkversion.h @ONLY)

if (ANDROID)
    add_subdirectory(ijksoundtouch)
    add_subdirectory(ijkj4a)
endif ()
