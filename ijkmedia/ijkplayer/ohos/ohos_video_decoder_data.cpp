/*
 * ohos_video_decoder_data.cpp
 *
 * Copyright (C) 2024 Huawei Device Co.,Ltd.
 *
 * This file is part of ijkPlayer.
 *
 * ijkPlayer is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * ijkPlayer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with ijkPlayer; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <multimedia/player_framework/native_averrors.h>
#include <multimedia/player_framework/native_avcodec_videodecoder.h>
#include "hilog/log.h"
#include "ohos_video_decoder_data.h"

CodecData::~CodecData()
{
    CodecData::ShutDown();
    formatInfo = nullptr;
    inputFrameCount_ = 0;
    outputFrameCount_ = 0;
}

void CodecData::Start()
{
    inputCond_.notify_all();
    outputCond_.notify_all();
}

void CodecData::ShutDown()
{
    inputCond_.notify_all();
    // Drain and destroy any buffers still in the input queue
    {
        std::unique_lock<std::mutex> lock(this->inputMutex_);
        std::queue<CodecBufferInfo> emptyQueue;
        swap(emptyQueue, this->inputBufferInfoQueue_);
    }
    outputCond_.notify_all();
    // Drain and destroy any buffers still in the output queue
    {
        std::unique_lock<std::mutex> lock(this->outputMutex_);
        std::queue<CodecBufferInfo> emptyQueue;
        swap(emptyQueue, this->outputBufferInfoQueue_);
    }
}

bool CodecData::HasInputBuffer()
{
    return !this->inputBufferInfoQueue_.empty();
}

int32_t CodecData::InputData(CodecBufferInfo &info, std::chrono::milliseconds time)
{
    if (info.buff_ == nullptr || this->formatInfo == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "DecoderData", "info.buff_ or formatInfo nullptr");
        return AV_ERR_UNKNOWN;
    }
    std::unique_lock<std::mutex> lock(this->inputMutex_);
    bool condRet =
        this->inputCond_.wait_for(lock, time, [this]() { return !this->inputBufferInfoQueue_.empty();});

    if (this->inputBufferInfoQueue_.empty()) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "DecoderData", "inputBufferInfoQueue_ is empty");
        return AV_ERR_TIMEOUT;
    }
    CodecBufferInfo bufferInfo = this->inputBufferInfoQueue_.front();
    this->inputBufferInfoQueue_.pop();
    this->inputFrameCount_++;
    lock.unlock();
    auto bufferInfoAddr = OH_AVBuffer_GetAddr(bufferInfo.buff_);
    auto infoAddr = OH_AVBuffer_GetAddr(info.buff_);
    if (bufferInfoAddr == nullptr || infoAddr == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "DecoderData", "ABbuffAddr is nullptr");
        return AV_ERR_IO;
    }
    memcpy(bufferInfoAddr, infoAddr, info.attr.size);
    OH_AVBuffer_SetBufferAttr(bufferInfo.buff_, &info.attr);
    info.bufferIndex = bufferInfo.bufferIndex;
    if (bufferInfo.attr.flags & AVCODEC_BUFFER_FLAGS_EOS) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "DecoderData", "Catch EOS");
        return AV_ERR_OK;
    }
    return AV_ERR_OK;
}

bool CodecData::OutputData(CodecBufferInfo &receiveInfo)
{
    std::unique_lock<std::mutex> lock(this->outputMutex_);
    bool ret = this->outputCond_.wait_for(lock, std::chrono::milliseconds(awaitTime_), [this]() {
                                              return !this->outputBufferInfoQueue_.empty();
                                          });
    if (!ret) {
        LOGE("OutputData outputBufferInfoQueue_ is empty");
        return false;
    }

    receiveInfo = this->outputBufferInfoQueue_.front();
    this->outputBufferInfoQueue_.pop();
    this->outputFrameCount_++;
    lock.unlock();
    return true;
}

bool CodecData::TryGetOutputBuffer(CodecBufferInfo &receiveInfo)
{
    std::unique_lock<std::mutex> lock(this->outputMutex_);
    auto ret = this->outputBufferInfoQueue_.empty();
    if (ret) {
        LOGE("TryGetOutputBuffer outputBufferInfoQueue_ is empty");
        return false;
    }
    receiveInfo = this->outputBufferInfoQueue_.front();
    lock.unlock();
    return true;
}

void CodecData::DropOutputBuffer(CodecBufferInfo &receiveInfo)
{
    std::unique_lock<std::mutex> lock(this->outputMutex_);
    auto ret = this->outputBufferInfoQueue_.empty();
    if (ret) {
        LOGE("DropOutputBuffer outputBufferInfoQueue_ is empty");
        return;
    }
    receiveInfo = this->outputBufferInfoQueue_.front();
    this->outputBufferInfoQueue_.pop();
    return;
}

void CodecData::InitOutputFormat(int32_t width, int32_t height)
{
    std::unique_lock<std::mutex> lock(outputMutex_);
    currentOutputFormat_.width = width;
    currentOutputFormat_.height = height;
    currentOutputFormat_.stride = width;
    currentOutputFormat_.sliceHeight = height;
}

bool CodecData::ConsumeResolutionChange(int32_t &outWidth, int32_t &outHeight)
{
    std::unique_lock<std::mutex> lock(outputMutex_);
    if (!resolutionChanged_.load()) {
        return false;
    }
    outWidth = currentOutputFormat_.width;
    outHeight = currentOutputFormat_.height;
    resolutionChanged_.store(false);
    return true;
}

void CodecData::DataCallback::OnCodecError(OH_AVCodec *codec, int32_t errorCode, void *userData)
{
    (void)codec;
    (void)errorCode;
    (void)userData;
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "VideoDecoder", "On decoder error, error code: %{public}d", errorCode);
}

void CodecData::DataCallback::OnCodecFormatChange(OH_AVCodec *videoEnc, OH_AVFormat *format, void *userData)
{
    (void)videoEnc;
    if (userData == nullptr || format == nullptr) {
        return;
    }
    CodecData *codecUserData = static_cast<CodecData *>(userData);
    std::unique_lock<std::mutex> lock(codecUserData->outputMutex_);
    BufferFormatInfo &cur = codecUserData->currentOutputFormat_;
    int32_t prevWidth = cur.width;
    int32_t prevHeight = cur.height;
    BufferFormatInfo fmt = cur;
    int32_t val = 0;
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_PIC_WIDTH, &val)) {
        fmt.width = val;
    }
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_PIC_HEIGHT, &val)) {
        fmt.height = val;
    }
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_STRIDE, &val)) {
        fmt.stride = val;
    }
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_SLICE_HEIGHT, &val)) {
        fmt.sliceHeight = val;
    }
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_CROP_TOP, &val)) {
        fmt.cropTop = val;
    }
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_CROP_BOTTOM, &val)) {
        fmt.cropBottom = val;
    }
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_CROP_LEFT, &val)) {
        fmt.cropLeft = val;
    }
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_CROP_RIGHT, &val)) {
        fmt.cropRight = val;
    }
    cur = fmt;
    if (fmt.width != prevWidth || fmt.height != prevHeight) {
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, "VideoDecoder",
            "Resolution changed: %{public}dx%{public}d -> %{public}dx%{public}d",
            prevWidth, prevHeight, fmt.width, fmt.height);
        codecUserData->resolutionChanged_.store(true);
    }
    codecUserData->outputCond_.notify_all();
}

void CodecData::DataCallback::OnNeedInputBuffer(OH_AVCodec *codec, uint32_t index, OH_AVBuffer *buffer,
    void *userData)
{
    if (userData == nullptr) {
        return;
    }
    (void)codec;
    CodecData *codecUserData = static_cast<CodecData *>(userData);
    std::unique_lock<std::mutex> lock(codecUserData->inputMutex_);
    codecUserData->inputBufferInfoQueue_.emplace(index, buffer);
    codecUserData->inputCond_.notify_all();
}

void CodecData::DataCallback::OnNewOutputBuffer(OH_AVCodec *codec, uint32_t index, OH_AVBuffer *buffer,
    void *userData)
{
    if (userData == nullptr) {
        return;
    }
    (void)codec;
    CodecData *codecUserData = static_cast<CodecData *>(userData);
    std::unique_lock<std::mutex> lock(codecUserData->outputMutex_);
    CodecBufferInfo info(index, buffer);
    info.bufferFormat = codecUserData->currentOutputFormat_;
    codecUserData->outputBufferInfoQueue_.push(info);
    codecUserData->outputCond_.notify_all();
}
