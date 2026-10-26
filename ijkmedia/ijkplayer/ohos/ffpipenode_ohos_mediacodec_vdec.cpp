/*
 * ffpipenode_ohos_mediacodec_vdec.cpp
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

#include "ffpipenode_ohos_mediacodec_vdec.h"

#include <algorithm>
#include <cstring>
#include <chrono>
#include <new>
#include <unistd.h>

extern "C" {
#include "libavcodec/bsf.h"
}
#include "hilog/log.h"
#include "ohos_video_decoder_data.h"
#include "ohos_video_decoder.h"

#define DATA_NUM_2 2
#define DATA_NUM_3 3
#define DATA_NUM_4 4
#define OHOS_VDEC_TAG "OHOSVDEC"
#define OHOS_VDEC_DOMAIN 0xFF00

#include "../../ijksdl/ohos/ijksdl_vout_ohos_nativewindow.h"
#include "../../ijksdl/ijksdl_fourcc.h"

int IjkohosVoutReleaseOutput(void *decoder, uint32_t bufferIndex, int render)
{
    if (!decoder) {
        return -1;
    }
    VideoDecoder *dec = static_cast<VideoDecoder *>(decoder);
    if (render) {
        return dec->RenderOutputBuffer(bufferIndex);
    }
    return dec->FreeOutputData(bufferIndex);
}

static const int NS_TO_US = 1000;
static const int MILLISECOND = 7;
static const int SUPPORT_NATIVE_BUFFER_FORMAT_SDK_VERSION = 22;
extern const char *OH_MD_KEY_VIDEO_NATIVE_BUFFER_FORMAT __attribute__((weak));

static const int32_t HEVC_NAL_TYPE_VPS = 32;
static const int32_t HEVC_NAL_TYPE_PPS = 34;
static const int32_t HEVC_NAL_TYPE_IRAP_MIN = 16;
static const int32_t HEVC_NAL_TYPE_IRAP_MAX = 23;

static int32_t AnnexBStartCodeLenAt(const uint8_t *p, const uint8_t *end)
{
    if (p + DATA_NUM_4 <= end && p[0] == 0 && p[1] == 0 && p[DATA_NUM_2] == 0 && p[DATA_NUM_3] == 1) {
        return DATA_NUM_4;
    }
    if (p + DATA_NUM_3 < end && p[0] == 0 && p[1] == 0 && p[DATA_NUM_2] == 1) {
        return DATA_NUM_3;
    }
    return 0;
}

// Scan Annex-B NALUs; report byte offsets of the first PS (VPS/SPS/PPS) and IRAP
static void HevcScanPsAndIrap(const uint8_t *data, int32_t size, int32_t *psOff, int32_t *irapOff)
{
    *psOff = -1;
    *irapOff = -1;
    if (data == nullptr || size <= 0) {
        return;
    }

    const uint8_t *end = data + size;
    for (const uint8_t *p = data; p + DATA_NUM_3 < end; ++p) {
        int32_t scLen = AnnexBStartCodeLenAt(p, end);
        if (scLen == 0) {
            continue;
        }
        const uint8_t *nal = p + scLen;
        if (nal >= end) {
            break;
        }
        int32_t nalType = (nal[0] >> 1) & 0x3f;
        if (*psOff < 0 && nalType >= HEVC_NAL_TYPE_VPS && nalType <= HEVC_NAL_TYPE_PPS) {
            *psOff = static_cast<int32_t>(p - data);
        }
        if (*irapOff < 0 && nalType >= HEVC_NAL_TYPE_IRAP_MIN && nalType <= HEVC_NAL_TYPE_IRAP_MAX) {
            *irapOff = static_cast<int32_t>(p - data);
        }
        if (*psOff >= 0 && *irapOff >= 0) {
            break;
        }
        p = nal + DATA_NUM_2 - 1;
    }
}

/*
 * hev1 packets may carry updated PS before IRAP that override extradata. Legacy
 * hevc_mp4toannexb prepends extradata before IRAP; move it before the first
 * packet PS so packet PS can override extradata in decode order.
 */
static int32_t HevcFixExtradataBeforePs(const uint8_t *src, int32_t size,
    const uint8_t *extra, int32_t extraSize, uint8_t **out)
{
    *out = nullptr;
    if (src == nullptr || size <= 0 || extra == nullptr || extraSize <= 0 || extraSize > size) {
        return size;
    }

    int32_t psOff = -1;
    int32_t irapOff = -1;
    HevcScanPsAndIrap(src, size, &psOff, &irapOff);
    if (psOff < 0 || irapOff < 0 || psOff >= irapOff) {
        return size;
    }

    int32_t misOff = irapOff - extraSize;
    if (misOff < psOff || misOff + extraSize > size || memcmp(src + misOff, extra, extraSize) != 0) {
        return size;
    }

    int32_t prefixLen = psOff;
    int32_t psBlockLen = misOff - psOff;
    int32_t suffixLen = size - irapOff;
    int64_t newLen = static_cast<int64_t>(prefixLen) + extraSize + psBlockLen + suffixLen;
    if (newLen != size || newLen > INT32_MAX) {
        return size;
    }
    int32_t newSize = static_cast<int32_t>(newLen);
    *out = static_cast<uint8_t *>(av_malloc((size_t)newSize + AV_INPUT_BUFFER_PADDING_SIZE));
    if (*out == nullptr) {
        return -1;
    }

    uint8_t *dst = *out;
    std::copy_n(src, prefixLen, dst);
    dst += prefixLen;
    std::copy_n(extra, extraSize, dst);
    dst += extraSize;
    std::copy_n(src + psOff, psBlockLen, dst);
    dst += psBlockLen;
    std::copy_n(src + irapOff, suffixLen, dst);
    std::fill(*out + newSize, *out + newSize + AV_INPUT_BUFFER_PADDING_SIZE, static_cast<uint8_t>(0));
    return newSize;
}

class IJKFF_Pipenode_Opaque {
public:
    IJKFF_Pipeline *pipeline;
    FormatInfo formatInfoEntry;
    CodecData codecData;
    VideoDecoder decoder;
    FFPlayer *ffp;
    AVCodecParameters *codecpar;
    AVPacket *pkt;
    SDL_Vout *weakVout;
    const AVBitStreamFilter *aVBitStreamFilter {nullptr};
    AVBSFContext *avbsfContext {nullptr};
    std::atomic_int64_t frameCount {0};
    SDL_Thread *enqueueThreadHandle {nullptr};
    void DecoderInput(AVPacket pkt);
    bool DecoderOutput(AVFrame *frame);
    bool DecoderOutputSurface(AVFrame *frame);
    bool TryGetDecoderOutput(AVFrame *frame);
    void DropDecoderOutput();
    std::atomic<bool> inputThreadExit;
};

struct HevcDecoderInputView {
    const uint8_t *data;
    int32_t size;
    uint8_t *allocBuf;
};

static void HevcPrepareInput(IJKFF_Pipenode_Opaque *opaque, const AVPacket &pkt, HevcDecoderInputView *view)
{
    view->data = pkt.data;
    view->size = pkt.size;
    view->allocBuf = nullptr;
    if (opaque->codecpar == nullptr || opaque->codecpar->codec_id != AV_CODEC_ID_HEVC ||
        opaque->avbsfContext == nullptr || opaque->avbsfContext->par_out == nullptr ||
        opaque->avbsfContext->par_out->extradata == nullptr ||
        opaque->avbsfContext->par_out->extradata_size <= 0) {
        return;
    }

    AVCodecParameters *parOut = opaque->avbsfContext->par_out;
    int32_t newSize = HevcFixExtradataBeforePs(pkt.data, pkt.size,
        parOut->extradata, parOut->extradata_size, &view->allocBuf);
    if (view->allocBuf != nullptr) {
        view->data = view->allocBuf;
        view->size = newSize;
    }
}

static void func_destroy(IJKFF_Pipenode *node)
{
    IJKFF_Pipenode_Opaque *opaque = static_cast<IJKFF_Pipenode_Opaque *>(node->opaque);
    /* Only touch vout if it is still the player's current vout (avoids UAF if destroy order differs). */
    if (opaque->weakVout && opaque->ffp && opaque->weakVout == opaque->ffp->vout) {
        SDL_VoutOhos_setReleaseOutputFunc(opaque->weakVout, nullptr);
    }
    opaque->weakVout = nullptr;
    if (opaque->codecpar)
    {
        avcodec_parameters_free(&opaque->codecpar);
        opaque->codecpar = nullptr;
    }
    if (opaque->avbsfContext) {
        av_bsf_free(&opaque->avbsfContext);
        opaque->avbsfContext = nullptr;
    }

    opaque->decoder.Release();
    opaque->codecData.ShutDown();
    opaque->~IJKFF_Pipenode_Opaque();
}

static IJKFF_Pipenode *destroy_and_fail(IJKFF_Pipenode *node)
{
    node->func_destroy = func_destroy;
    func_destroy(node);
    SDL_DestroyMutexP(&node->mutex);
    free(node->opaque);
    free(node);
    return nullptr;
}

void IJKFF_Pipenode_Opaque::DecoderInput(AVPacket pkt)
{
    // Reorder misplaced init extradata before in-band PS for hev1 HEVC IRAP packets
    HevcDecoderInputView input = { pkt.data, pkt.size, nullptr };
    HevcPrepareInput(this, pkt, &input);

    int32_t ret = 0;
    int inputTime = 30;
    CodecBufferInfo codecBufferInfo;
    codecBufferInfo.buff_ = OH_AVBuffer_Create(input.size);
    if (codecBufferInfo.buff_ == nullptr) {
        av_free(input.allocBuf);
        return;
    }
    auto bufferAddr = OH_AVBuffer_GetAddr(codecBufferInfo.buff_);
    if (bufferAddr == nullptr) {
        OH_AVBuffer_Destroy(codecBufferInfo.buff_);
        av_free(input.allocBuf);
        return;
    }
    std::copy_n(input.data, input.size, bufferAddr);
    codecBufferInfo.attr.size = input.size;
    codecBufferInfo.attr.pts = pkt.pts;
    if (pkt.flags == 1) {
        codecBufferInfo.attr.flags = AVCODEC_BUFFER_FLAGS_CODEC_DATA|AVCODEC_BUFFER_FLAGS_SYNC_FRAME;
    } else {
        codecBufferInfo.attr.flags = AVCODEC_BUFFER_FLAGS_NONE;
    }

    ret = this->codecData.InputData(codecBufferInfo, std::chrono::milliseconds(inputTime));
    if (ret == 0) {
        int32_t pushRet = this->decoder.PushInputData(codecBufferInfo);
        if (pushRet != 0) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, OHOS_VDEC_DOMAIN, OHOS_VDEC_TAG,
                "PushInputData failed ret=%{public}d", pushRet);
        }
    }
    OH_AVBuffer_Destroy(codecBufferInfo.buff_);
    av_free(input.allocBuf);
}

void IJKFF_Pipenode_Opaque::DropDecoderOutput()
{
    CodecBufferInfo codecBufferInfoReceive;
    this->codecData.DropOutputBuffer(codecBufferInfoReceive);
    this->decoder.FreeOutputData(codecBufferInfoReceive.bufferIndex);
}

bool IJKFF_Pipenode_Opaque::DecoderOutput(AVFrame *frame)
{
    return DecoderOutputSurface(frame);
}

bool IJKFF_Pipenode_Opaque::DecoderOutputSurface(AVFrame *frame)
{
    CodecBufferInfo codecBufferInfoReceive;
    bool ret = this->codecData.OutputData(codecBufferInfoReceive);
    if (!ret) {
        LOGE("%s:%d OutputData failed", __FUNCTION__, __LINE__);
        return false;
    }

    if (codecBufferInfoReceive.attr.flags & AVCODEC_BUFFER_FLAGS_EOS) {
        decoder.FreeOutputData(codecBufferInfoReceive.bufferIndex);
        this->codecData.ShutDown();
        LOGE("%s:%d EOS received", __FUNCTION__, __LINE__);
        return false;
    }

    if (!weakVout) {
        LOGE("%s:%d surface mode but vout is null", __FUNCTION__, __LINE__);
        decoder.FreeOutputData(codecBufferInfoReceive.bufferIndex);
        return false;
    }

    int32_t newWidth = 0;
    int32_t newHeight = 0;
    if (this->codecData.ConsumeResolutionChange(newWidth, newHeight)) {
        // opaque-owned codecpar (from viddec.avctx), width/height only touched on this thread
        codecpar->width = newWidth;
        codecpar->height = newHeight;
        LOGI("Resolution change consumed: %dx%d", newWidth, newHeight);
    }

    av_frame_unref(frame);
    frame->format = IJK_AV_PIX_FMT__HOS_AVCODEC;
    frame->width = codecpar->width;
    frame->height = codecpar->height;
    frame->pts = codecBufferInfoReceive.attr.pts;
    frame->sample_aspect_ratio = codecpar->sample_aspect_ratio;
    frame->opaque = SDL_VoutOhos_obtainBufferProxy(weakVout, &decoder, codecBufferInfoReceive.bufferIndex);
    if (!frame->opaque) {
        LOGE("%s:%d SDL_VoutOhos_obtainBufferProxy failed", __FUNCTION__, __LINE__);
        decoder.FreeOutputData(codecBufferInfoReceive.bufferIndex);
        return false;
    }
    return true;
}

bool IJKFF_Pipenode_Opaque::TryGetDecoderOutput(AVFrame *frame)
{
    CodecBufferInfo codecBufferInfoReceive;
    bool ret = false;
    ret = this->codecData.TryGetOutputBuffer(codecBufferInfoReceive);
    if (!ret) {
        return false;
    }
    OH_AVBuffer_GetBufferAttr(codecBufferInfoReceive.buff_, &codecBufferInfoReceive.attr);
    frame->pts = codecBufferInfoReceive.attr.pts;
    frame->pkt_dts = codecBufferInfoReceive.attr.pts;
    return true;
}

static bool try_get_video_frame(FFPlayer *ffp, Decoder *d, AVFrame *frame, IJKFF_Pipenode_Opaque *opaque)
{
    bool gotPicture = false;
    if ((gotPicture = opaque->TryGetDecoderOutput(frame)) == false) {
        return false;
    }
    return true;
}

static int ohos_mediacodec_enqueue_thread_func(void *arg)
{
    IJKFF_Pipenode_Opaque *opaque = static_cast<IJKFF_Pipenode_Opaque *>(arg);
    FFPlayer *ffp = opaque->ffp;
    Decoder *d = &(ffp->is->viddec);
    OH_LOG_Print(LOG_APP, LOG_INFO, OHOS_VDEC_DOMAIN, OHOS_VDEC_TAG, "enqueue thread started");
    av_log(ffp, AV_LOG_INFO, "ohos_mediacodec_enqueue_thread: input thread started\n");
    while (opaque->inputThreadExit) {
        bool gotPkt = true;
        if (opaque->codecData.HasInputBuffer()) {
            AVPacket pkt;
            do {
                if (d->queue->nb_packets == 0) {
                    SDL_CondSignal(d->empty_queue_cond);
                }
                if (ffp_packet_queue_get_or_buffering(ffp, d->queue, &pkt, &d->pkt_serial, &d->finished) < 0) {
                    LOGE("ffp_packet_queue_get_or_buffering failed");
                    opaque->inputThreadExit = false;
                    gotPkt = false;
                    return -1;
                }
                if (ffp_is_flush_packet(&pkt)) {
                    d->finished = 0;
                    d->next_pts = d->start_pts;
                    d->next_pts_tb = d->start_pts_tb;
                    if (opaque->avbsfContext)
                        av_bsf_flush(opaque->avbsfContext);
                    // 不要在这里 OH_VideoDecoder_Flush：它会清掉 SPS/PPS 并让旧
                    // buffer index 失效，seek 后要么一帧不出、要么 RenderOutputBuffer
                    // 报错，播放直接停住。seek 的旧帧问题改用丢弃过期输出帧的方式解。
                    av_packet_unref(&pkt);
                    gotPkt = false;
                    continue;
                }
            } while (d->queue->serial != d->pkt_serial);

            if (!pkt.data || pkt.size <= 0) {
                av_packet_unref(&pkt);
                continue;
            }

            int bsfRret = av_bsf_send_packet(opaque->avbsfContext, &pkt);
            if (bsfRret == AVERROR(EINVAL)) {
                av_bsf_flush(opaque->avbsfContext);
                bsfRret = av_bsf_send_packet(opaque->avbsfContext, &pkt);
            }
            if (bsfRret < 0) {
                OH_LOG_Print(LOG_APP, LOG_ERROR, OHOS_VDEC_DOMAIN, OHOS_VDEC_TAG,
                    "av_bsf_send_packet failed %{public}d", bsfRret);
                LOGE("av_bsf_send_packet failed %d", bsfRret);
                gotPkt = false;
                av_packet_unref(&pkt);
            }
            while (bsfRret >= 0) {
                bsfRret = av_bsf_receive_packet(opaque->avbsfContext, &pkt);
                if (bsfRret == AVERROR_EOF) {
                    d->finished = d->pkt_serial;
                    avcodec_flush_buffers(d->avctx);
                    av_packet_unref(&pkt);
                    LOGE("av_bsf_receive_packet failed");
                    gotPkt = false;
                }
            }
            if (gotPkt && (!pkt.data || pkt.size <= 0)) {
                av_packet_unref(&pkt);
                gotPkt = false;
            }
            if (gotPkt) {
                av_log(ffp, AV_LOG_DEBUG, "ohos_mediacodec_enqueue_thread: feeding packet to decoder, size=%d, pts=%lld\n",
                       pkt.size, (long long)pkt.pts);
                opaque->DecoderInput(pkt);
                av_packet_unref(&pkt);
            }
        }
        usleep(1 * NS_TO_US);
    }

    av_log(ffp, AV_LOG_INFO, "ohos_mediacodec_enqueue_thread: input thread exiting\n");
    return 0;
}

void drop_video_frame(IJKFF_Pipenode_Opaque *opaque)
{
    if (opaque) {
        opaque->DropDecoderOutput();
    }
}

static int decoder_decode_ohos_frame(FFPlayer *ffp, Decoder *d, AVFrame *frame, IJKFF_Pipenode_Opaque *opaque)
{
    int gotPicture = -1;
    if (opaque->DecoderOutput(frame)) {
        gotPicture = 1;
    }
    return gotPicture;
}

static int get_video_frame(FFPlayer *ffp, AVFrame *frame, IJKFF_Pipenode_Opaque *opaque)
{
    VideoState *is = ffp->is;
    if (is == nullptr) {
        return -1;
    }
    int gotPicture = 0;

    ffp_video_statistic_l(ffp);
    if (try_get_video_frame(ffp, &is->viddec, frame, opaque)) {
        double dpts = NAN;
        if (frame->pts != AV_NOPTS_VALUE)
            dpts = av_q2d(is->video_st->time_base) * frame->pts;

        frame->sample_aspect_ratio = av_guess_sample_aspect_ratio(is->ic, is->video_st, frame);

        if (ffp->framedrop>0 || (ffp->framedrop && ffp_get_master_sync_type(is) != AV_SYNC_VIDEO_MASTER)) {
            ffp->stat.decode_frame_count++;
            if (frame->pts != AV_NOPTS_VALUE) {
                double diff = dpts - ffp_get_master_clock(is);
                if (!isnan(diff) && fabs(diff) < AV_NOSYNC_THRESHOLD &&
                    diff - is->frame_last_filter_delay < 0 &&
                    is->viddec.pkt_serial == is->vidclk.serial &&
                    is->videoq.nb_packets) {
                    is->frame_drops_early++;
                    is->continuous_frame_drops_early++;
                    if (is->continuous_frame_drops_early > ffp->framedrop) {
                        gotPicture = decoder_decode_ohos_frame(ffp, &is->viddec, frame, opaque);
                        is->continuous_frame_drops_early = 0;
                    } else {
                        ffp->stat.drop_frame_count++;
                        if (ffp->stat.decode_frame_count > 0) {
                            ffp->stat.drop_frame_rate = static_cast<float>(ffp->stat.drop_frame_count) /
                                static_cast<float>(ffp->stat.decode_frame_count);
                        }
                        drop_video_frame(opaque);
                        gotPicture = 0;
                    }
                } else {
                    gotPicture = decoder_decode_ohos_frame(ffp, &is->viddec, frame, opaque);
                }
            } else if (is->continuous_frame_drops_early <= ffp->framedrop) {
                ffp->stat.drop_frame_count++;
                if (ffp->stat.decode_frame_count > 0) {
                    ffp->stat.drop_frame_rate = static_cast<float>(ffp->stat.drop_frame_count) /
                        static_cast<float>(ffp->stat.decode_frame_count);
                }
                drop_video_frame(opaque);
                gotPicture = 0;
            }
        } else {
            gotPicture = decoder_decode_ohos_frame(ffp, &is->viddec, frame, opaque);
        }
    }
    return gotPicture;
}

static int ffplay_video_ohos_thread(FFPlayer *ffp, IJKFF_Pipenode_Opaque *opaque)
{
    VideoState *is = ffp->is;
    double pts;
    double duration;
    int ret;
    AVRational tb = is->video_st->time_base;
    AVRational frameRate = av_guess_frame_rate(is->ic, is->video_st, NULL);

    OH_LOG_Print(LOG_APP, LOG_INFO, OHOS_VDEC_DOMAIN, OHOS_VDEC_TAG, "video thread started");
    av_log(ffp, AV_LOG_INFO, "ffplay_video_ohos_thread: started (hardware decode), tb=%d/%d, frameRate=%d/%d\n",
           tb.num, tb.den, frameRate.num, frameRate.den);

    ffp_notify_msg2(ffp, FFP_MSG_VIDEO_ROTATION_CHANGED, ffp_get_video_rotate_degrees(ffp));

    AVFrame *frame = av_frame_alloc();
    if (!frame) {
        return AVERROR(ENOMEM);
    }
    frame->format = AV_PIX_FMT_NONE;

    opaque->inputThreadExit = true;
    opaque->enqueueThreadHandle = SDL_CreateThread(ohos_mediacodec_enqueue_thread_func,
                                                 "ohos_mediacodec_input_thread", opaque);
    if (!opaque->enqueueThreadHandle) {
        LOGE("%s: SDL_CreateThreadEx failed\n", __func__);
        av_frame_free(&frame);
        return AVERROR(ENOMEM);
    }

    for (;;) {
        if (is->abort_request) {
            goto the_end;
        }

        ret = get_video_frame(ffp, frame, opaque);
        if (ret < 0 || opaque->inputThreadExit == false) {
            goto the_end;
        }

        if (!ret) {
            usleep(5 * NS_TO_US);
            continue;
        }

        duration = (frameRate.num && frameRate.den ? av_q2d((AVRational){frameRate.den, frameRate.num}) : 0);
        pts = (frame->pts == AV_NOPTS_VALUE) ? NAN : frame->pts * av_q2d(tb);
        av_log(ffp, AV_LOG_DEBUG, "ffplay_video_ohos_thread: decoded frame, pts=%lld, w=%d, h=%d, format=%d\n",
               (long long)frame->pts, frame->width, frame->height, frame->format);
        ret = ffp_queue_picture(ffp, frame, pts, duration, AV_NOPTS_VALUE, is->viddec.pkt_serial);
        if (ret) {
            if (frame->opaque && opaque->weakVout) {
                SDL_OhosAVCodecBufferProxy *ohProxy = static_cast<SDL_OhosAVCodecBufferProxy *>(frame->opaque);
                SDL_VoutOhos_releaseBufferProxyP(opaque->weakVout, &ohProxy, false);
                frame->opaque = nullptr;
            }
        }
        av_frame_unref(frame);
        if (ret < 0) {
            goto the_end;
        }
    }
 the_end:
    opaque->inputThreadExit = false;
    if (opaque->enqueueThreadHandle) {
        SDL_WaitThread(opaque->enqueueThreadHandle, NULL);
        opaque->enqueueThreadHandle = nullptr;
    }

    av_bsf_free(&opaque->avbsfContext);
    av_frame_free(&frame);
    return 0;
}


static int func_run_sync(IJKFF_Pipenode *node)
{
    IJKFF_Pipenode_Opaque *opaque = static_cast<IJKFF_Pipenode_Opaque *>(node->opaque);
    return ffplay_video_ohos_thread(opaque->ffp, opaque);
}

static int GetAvbsfContest(std::string bsfName, IJKFF_Pipenode_Opaque *decoderSample, AVCodecParameters *codecpar)
{
    decoderSample->aVBitStreamFilter = av_bsf_get_by_name(bsfName.c_str());
    if (decoderSample->aVBitStreamFilter == nullptr) {
        return -1;
    }

    if (av_bsf_alloc(decoderSample->aVBitStreamFilter, &decoderSample->avbsfContext) < 0) {
        return -1;
    }

    if (avcodec_parameters_copy(decoderSample->avbsfContext->par_in, codecpar) < 0) {
        return -1;
    }

    if (av_bsf_init(decoderSample->avbsfContext) < 0) {
        av_log(decoderSample->ffp, AV_LOG_ERROR, "GetAvbsfContest: av_bsf_init failed for bsf=%s\n", bsfName.c_str());
        return -1;
    }
    av_log(decoderSample->ffp, AV_LOG_INFO, "GetAvbsfContest: bitstream filter '%s' initialized\n", bsfName.c_str());
    return 0;
}

static bool InitOhosVideoDecoderByCodec(IJKFF_Pipenode_Opaque *decoderSample, std::string &bsfName)
{
    switch (decoderSample->codecpar->codec_id) {
        case AV_CODEC_ID_H264:
            bsfName = "h264_mp4toannexb";
            if (decoderSample->decoder.Create(OH_AVCODEC_MIMETYPE_VIDEO_AVC) != 0)
                return false;
            av_log(decoderSample->ffp, AV_LOG_INFO, "InitOhosVideoDecoderByCodec: H264 codec, bsf=h264_mp4toannexb\n");
            return true;
        case AV_CODEC_ID_HEVC:
            bsfName = "hevc_mp4toannexb";
            if (decoderSample->decoder.Create(OH_AVCODEC_MIMETYPE_VIDEO_HEVC) != 0)
                return false;
            av_log(decoderSample->ffp, AV_LOG_INFO, "InitOhosVideoDecoderByCodec: HEVC codec, bsf=hevc_mp4toannexb\n");
            return true;
        default:
            LOGE("InitOhosVideoDecoderByCodec: unsupported codec_id = %d\n", decoderSample->codecpar->codec_id);
            return false;
    }
}

IJKFF_Pipenode *ffpipenode_create_video_decoder_from_ohos_mediacodec(FFPlayer *ffp, IJKFF_Pipeline *pipeline,
    SDL_Vout *vout, void* nativeWindow)
{
    std::string bsfName;
    IJKFF_Pipenode *node = ffpipenode_alloc(0);
    void *opaque_memory = calloc(1, sizeof(IJKFF_Pipenode_Opaque));
    if (!opaque_memory) {
        SDL_DestroyMutexP(&node->mutex);
        free(node);
        return nullptr;
    }
    IJKFF_Pipenode_Opaque *decoderSample = new (opaque_memory) IJKFF_Pipenode_Opaque();
    node->opaque = decoderSample;
    decoderSample->ffp = ffp;
    decoderSample->pipeline = pipeline;
    decoderSample->weakVout = vout;
    decoderSample->decoder.nativeWindow_ = nativeWindow;
    if (vout) {
        SDL_VoutOhos_setReleaseOutputFunc(vout, nativeWindow ? IjkohosVoutReleaseOutput : nullptr);
    }
    decoderSample->codecpar = avcodec_parameters_alloc();
    if (!decoderSample->codecpar) {
        return destroy_and_fail(node);
    }

    if (avcodec_parameters_from_context(decoderSample->codecpar, ffp->is->viddec.avctx) < 0) {
        return destroy_and_fail(node);
    }

    decoderSample->formatInfoEntry.fps = av_q2d(av_guess_frame_rate(ffp->is->ic, ffp->is->video_st, NULL));
    decoderSample->formatInfoEntry.videoHeight = decoderSample->codecpar->height;
    decoderSample->formatInfoEntry.videoWidth = decoderSample->codecpar->width;
    decoderSample->codecData.formatInfo = &decoderSample->formatInfoEntry;
    decoderSample->codecData.InitOutputFormat(decoderSample->codecpar->width, decoderSample->codecpar->height);

    if (!InitOhosVideoDecoderByCodec(decoderSample, bsfName)) {
        LOGE("InitOhosVideoDecoderByCodec failed");
        return destroy_and_fail(node);
    }

    if (GetAvbsfContest(bsfName, decoderSample, ffp->is->video_st->codecpar) < 0) {
        LOGE("GetAvbsfContest failed");
        return destroy_and_fail(node);
    }

    if (decoderSample->decoder.Config(&decoderSample->codecData) != 0 ||
        decoderSample->decoder.Start() != 0) {
        LOGE("OHOS VideoDecoder Config/Start failed");
        return destroy_and_fail(node);
    }
    decoderSample->codecData.Start();

    OH_LOG_Print(LOG_APP, LOG_INFO, OHOS_VDEC_DOMAIN, OHOS_VDEC_TAG,
        "HW decoder created width=%{public}d height=%{public}d",
        decoderSample->codecpar->width, decoderSample->codecpar->height);
    av_log(ffp, AV_LOG_INFO, "ffpipenode_create_video_decoder_from_ohos_mediacodec: HW decoder created and started, width=%d, height=%d, fps=%.2f\n",
           decoderSample->codecpar->width, decoderSample->codecpar->height, decoderSample->formatInfoEntry.fps);

    node->func_destroy = func_destroy;
    node->func_run_sync = func_run_sync;
    return node;
}