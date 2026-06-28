/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "StreamPlayer.h"

#include <ao/ao.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswresample/swresample.h>
#include <libavutil/opt.h>

@implementation StreamPlayer

@synthesize delegate = _delegate;
@synthesize volume = _volume;
@synthesize muted = _muted;
@synthesize currentURL = _currentURL;

+ (instancetype)sharedPlayer
{
    static StreamPlayer *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _volume = 1.0f;
        _muted = NO;
        _isPlaying = NO;
        _shouldStop = NO;
        _audioStreamIndex = -1;
        _decodeErrorCount = 0;
        _lastMetadata = nil;
        _metadataCheckCounter = 0;

        ao_initialize();
    }
    return self;
}

- (void)dealloc
{
    [self close];
    ao_shutdown();
    [super dealloc];
}

#pragma mark - Properties

- (BOOL)isPlaying
{
    @synchronized(self) {
        return _isPlaying;
    }
}

- (void)setVolume:(float)volume
{
    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;
    _volume = volume;
}

- (void)setCurrentURL:(NSString *)url
{
    if (_currentURL != url) {
        [_currentURL release];
        _currentURL = [url copy];
    }
}

- (NSString *)currentURL
{
    return [[_currentURL retain] autorelease];
}

#pragma mark - Public API

- (BOOL)openURL:(NSString *)urlString error:(NSError **)error
{
    if (urlString == nil || [urlString length] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"StreamPlayer"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"URL is nil or empty"}];
        }
        return NO;
    }

    @synchronized(self) {
        [self close];

        const char *url = [urlString UTF8String];
        if (!url) {
            if (error) {
                *error = [NSError errorWithDomain:@"StreamPlayer"
                                             code:-2
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL string encoding"}];
            }
            return NO;
        }

        // ---- Open stream with FFmpeg ---- //
        _formatCtx = avformat_alloc_context();
        if (!_formatCtx) {
            if (error) {
                *error = [NSError errorWithDomain:@"StreamPlayer"
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to allocate format context"}];
            }
            return NO;
        }

        // Set network options for streaming
        AVDictionary *opts = NULL;
        av_dict_set(&opts, "timeout", "15000000", 0);   // 15 s timeout
        av_dict_set(&opts, "reconnect", "1", 0);
        av_dict_set(&opts, "reconnect_streamed", "1", 0);
        av_dict_set(&opts, "reconnect_delay_max", "5", 0);
        av_dict_set(&opts, "icy", "1", 0);               // Enable ICY metadata parsing

        int ret = avformat_open_input((AVFormatContext **)&_formatCtx, url, NULL, &opts);
        av_dict_free(&opts);

        if (ret < 0) {
            char errBuf[256];
            av_strerror(ret, errBuf, sizeof(errBuf));
            NSLog(@"[StreamPlayer] avformat_open_input failed: %s (code %d)", errBuf, ret);
            if (error) {
                *error = [NSError errorWithDomain:@"StreamPlayer"
                                             code:ret
                                         userInfo:@{NSLocalizedDescriptionKey:
                                             [NSString stringWithFormat:@"Failed to open stream: %s", errBuf]}];
            }
            if (_formatCtx) {
                avformat_close_input((AVFormatContext **)&_formatCtx);
                _formatCtx = NULL;
            }
            return NO;
        }
        NSLog(@"[StreamPlayer] Opened stream for URL: %s", url);

        // Find stream info
        ret = avformat_find_stream_info((AVFormatContext *)_formatCtx, NULL);
        if (ret < 0) {
            char errBuf[256]; av_strerror(ret, errBuf, sizeof(errBuf));
            NSLog(@"[StreamPlayer] avformat_find_stream_info failed: %s", errBuf);
            if (error) {
                *error = [NSError errorWithDomain:@"StreamPlayer"
                                             code:ret
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to find stream info"}];
            }
            avformat_close_input((AVFormatContext **)&_formatCtx);
            _formatCtx = NULL;
            return NO;
        }

        // Read initial ICY metadata
        {
            AVFormatContext *fmtCtx = (AVFormatContext *)_formatCtx;
            AVDictionaryEntry *tag = NULL;
            NSMutableDictionary *meta = [NSMutableDictionary dictionary];
            while ((tag = av_dict_get(fmtCtx->metadata, "", tag,
                                      AV_DICT_IGNORE_SUFFIX)) != NULL) {
                NSString *key = [NSString stringWithUTF8String: tag->key];
                NSString *val = [NSString stringWithUTF8String: tag->value];
                if (key && val) {
                    [meta setObject:val forKey:key];
                }
                NSLog(@"[StreamPlayer] ICY metadata: %s = %s", tag->key, tag->value);
            }
            [_lastMetadata release];
            _lastMetadata = [meta retain];
        }

        // Find audio stream
        AVFormatContext *fmtCtx = (AVFormatContext *)_formatCtx;
        _audioStreamIndex = -1;
        for (unsigned int i = 0; i < fmtCtx->nb_streams; i++) {
            if (fmtCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
                _audioStreamIndex = i;
                break;
            }
        }

        if (_audioStreamIndex < 0) {
            NSLog(@"[StreamPlayer] No audio stream found");
            if (error) {
                *error = [NSError errorWithDomain:@"StreamPlayer"
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey: @"No audio stream found"}];
            }
            avformat_close_input((AVFormatContext **)&_formatCtx);
            _formatCtx = NULL;
            return NO;
        }

        // Set up codec
        AVCodecParameters *codecPar = fmtCtx->streams[_audioStreamIndex]->codecpar;
        NSLog(@"[StreamPlayer] Codec ID: %d, sample rate: %d, channels: %d",
              codecPar->codec_id, codecPar->sample_rate, codecPar->ch_layout.nb_channels);

        const AVCodec *codec = avcodec_find_decoder(codecPar->codec_id);
        if (!codec) {
            if (error) {
                *error = [NSError errorWithDomain:@"StreamPlayer"
                                             code:3
                                         userInfo:@{NSLocalizedDescriptionKey: @"Audio codec not found"}];
            }
            avformat_close_input((AVFormatContext **)&_formatCtx);
            _formatCtx = NULL;
            return NO;
        }

        _codecCtx = avcodec_alloc_context3(codec);
        if (!_codecCtx) {
            if (error) {
                *error = [NSError errorWithDomain:@"StreamPlayer"
                                             code:4
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to allocate codec context"}];
            }
            avformat_close_input((AVFormatContext **)&_formatCtx);
            _formatCtx = NULL;
            return NO;
        }

        avcodec_parameters_to_context((AVCodecContext *)_codecCtx, codecPar);

        ret = avcodec_open2((AVCodecContext *)_codecCtx, codec, NULL);
        if (ret < 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"StreamPlayer"
                                             code:ret
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to open codec"}];
            }
            avcodec_free_context((AVCodecContext **)&_codecCtx);
            _codecCtx = NULL;
            avformat_close_input((AVFormatContext **)&_formatCtx);
            _formatCtx = NULL;
            return NO;
        }

        // Set up resampler (convert to stereo S16)
        AVCodecContext *codecCtx = (AVCodecContext *)_codecCtx;
        int outChannels = 2;
        AVChannelLayout outLayout = AV_CHANNEL_LAYOUT_STEREO;

        ret = swr_alloc_set_opts2((SwrContext **)&_swrCtx,
                                  &outLayout, AV_SAMPLE_FMT_S16, codecCtx->sample_rate,
                                  &codecCtx->ch_layout, codecCtx->sample_fmt, codecCtx->sample_rate,
                                  0, NULL);
        if (ret < 0 || swr_init((SwrContext *)_swrCtx) < 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"StreamPlayer"
                                             code:5
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to initialize resampler"}];
            }
            avcodec_free_context((AVCodecContext **)&_codecCtx);
            _codecCtx = NULL;
            avformat_close_input((AVFormatContext **)&_formatCtx);
            _formatCtx = NULL;
            return NO;
        }

        // Allocate frame and packet
        _frame = av_frame_alloc();
        _packet = av_packet_alloc();
        if (!_frame || !_packet) {
            if (error) {
                *error = [NSError errorWithDomain:@"StreamPlayer"
                                             code:6
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to allocate frame/packet"}];
            }
            [self close];
            return NO;
        }

        // ---- Set up libao ---- //
        int driver = ao_default_driver_id();
        if (driver < 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"StreamPlayer"
                                             code:7
                                         userInfo:@{NSLocalizedDescriptionKey: @"No audio output driver found"}];
            }
            [self close];
            return NO;
        }

        ao_sample_format aoFmt;
        memset(&aoFmt, 0, sizeof(ao_sample_format));
        aoFmt.bits = 16;
        aoFmt.channels = outChannels;
        aoFmt.rate = codecCtx->sample_rate;
        aoFmt.byte_format = AO_FMT_NATIVE;

        _aoDev = ao_open_live(driver, &aoFmt, NULL);
        if (!_aoDev) {
            if (error) {
                *error = [NSError errorWithDomain:@"StreamPlayer"
                                             code:8
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to open audio device"}];
            }
            [self close];
            return NO;
        }

        [self setCurrentURL:urlString];
        return YES;
    }
}

- (void)play
{
    if (_isPlaying || !_formatCtx) {
        return;
    }

    _shouldStop = NO;
    _isPlaying = YES;
    _decodeErrorCount = 0;

    _playbackThread = [[NSThread alloc] initWithTarget:self
                                              selector:@selector(playbackLoop)
                                                object:nil];
    [_playbackThread start];

    if (_delegate != nil && [_delegate respondsToSelector:@selector(streamPlayerDidStartPlaying:)]) {
        [_delegate streamPlayerDidStartPlaying:self];
    }

    // Send initial ICY metadata immediately so the UI can show StreamTitle, icy-url, etc.
    if (_lastMetadata && [_lastMetadata count] > 0 &&
        _delegate != nil && [_delegate respondsToSelector:@selector(streamPlayer:didUpdateMetadata:)]) {
        [_delegate streamPlayer:self didUpdateMetadata:_lastMetadata];
    }
}

- (void)stop
{
    @synchronized(self) {
        if (!_isPlaying) {
            return;
        }
        _shouldStop = YES;
    }

    // Wait for playback thread to finish
    while (_playbackThread && ![_playbackThread isFinished]) {
        [NSThread sleepForTimeInterval:0.01];
    }

    [_playbackThread release];
    _playbackThread = nil;

    _isPlaying = NO;

    if (_delegate != nil && [_delegate respondsToSelector:@selector(streamPlayerDidStop:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_delegate streamPlayerDidStop:self];
        });
    }
}

- (void)close
{
    [self stop];

    if (_audioBuffer) {
        free(_audioBuffer);
        _audioBuffer = NULL;
        _audioBufferSize = 0;
    }

    if (_frame) {
        av_frame_free((AVFrame **)&_frame);
    }
    if (_packet) {
        av_packet_free((AVPacket **)&_packet);
    }
    if (_swrCtx) {
        swr_free((SwrContext **)&_swrCtx);
    }
    if (_codecCtx) {
        avcodec_free_context((AVCodecContext **)&_codecCtx);
    }
    if (_formatCtx) {
        avformat_close_input((AVFormatContext **)&_formatCtx);
    }
    if (_aoDev) {
        ao_close((ao_device *)_aoDev);
        _aoDev = NULL;
    }

    _audioStreamIndex = -1;
    _decodeErrorCount = 0;
    [_lastMetadata release];
    _lastMetadata = nil;
    _metadataCheckCounter = 0;
    [self setCurrentURL:nil];
}

#pragma mark - Playback Loop

- (void)playbackLoop
{
    @autoreleasepool {
        if (!_formatCtx || !_codecCtx || !_swrCtx || !_aoDev || !_packet) {
            _isPlaying = NO;
            return;
        }

        int frameCount = 0;

        while (!_shouldStop) {
            if (!_formatCtx) break;

            @autoreleasepool {
                AVPacket *pkt = (AVPacket *)_packet;
                int ret = av_read_frame((AVFormatContext *)_formatCtx, pkt);
                if (ret < 0) {
                    if (ret == AVERROR_EOF || ret == AVERROR(EAGAIN)) {
                        break;
                    }
                    // Error reading frame
                    if (_delegate != nil && [_delegate respondsToSelector:@selector(streamPlayer:didFailWithError:)]) {
                        NSError *err = [NSError errorWithDomain:@"StreamPlayer"
                                                           code:ret
                                                       userInfo:@{NSLocalizedDescriptionKey: @"Error reading stream"}];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self->_delegate streamPlayer:self didFailWithError:err];
                        });
                    }
                    break;
                }

                if (pkt->stream_index == _audioStreamIndex) {
                    [self decodePacket];
                    frameCount++;
                    if (frameCount == 1) {
                        NSLog(@"[StreamPlayer] First audio frame decoded");
                    }
                }

                av_packet_unref(pkt);

                // Poll ICY metadata every ~50 frames for changes
                if (frameCount % 50 == 0 && _formatCtx) {
                    AVFormatContext *fmtCtx = (AVFormatContext *)_formatCtx;
                    AVDictionaryEntry *tag = NULL;
                    NSMutableDictionary *currentMeta = [NSMutableDictionary dictionary];
                    while ((tag = av_dict_get(fmtCtx->metadata, "", tag,
                                              AV_DICT_IGNORE_SUFFIX)) != NULL) {
                        NSString *key = [NSString stringWithUTF8String: tag->key];
                        NSString *val = [NSString stringWithUTF8String: tag->value];
                        if (key && val) {
                            [currentMeta setObject:val forKey:key];
                        }
                    }

                    if (![_lastMetadata isEqualToDictionary:currentMeta]) {
                        [_lastMetadata release];
                        _lastMetadata = [currentMeta retain];
                        if (_delegate != nil &&
                            [_delegate respondsToSelector:@selector(streamPlayer:didUpdateMetadata:)]) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [self->_delegate streamPlayer:self
                                            didUpdateMetadata:currentMeta];
                            });
                        }
                    }
                }
            }
        }

        _isPlaying = NO;

        if (_delegate != nil && [_delegate respondsToSelector:@selector(streamPlayerDidStop:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_delegate streamPlayerDidStop:self];
            });
        }
    }
}

- (void)decodePacket
{
    if (!_codecCtx || !_swrCtx || !_aoDev || !_packet) {
        return;
    }

    AVCodecContext *codecCtx = (AVCodecContext *)_codecCtx;
    SwrContext *swrCtx = (SwrContext *)_swrCtx;
    ao_device *aoDev = (ao_device *)_aoDev;
    AVPacket *pkt = (AVPacket *)_packet;
    AVFrame *frame = (AVFrame *)_frame;

    int ret = avcodec_send_packet(codecCtx, pkt);
    if (ret < 0) {
        _decodeErrorCount++;
        if (_decodeErrorCount > 10) {
            _shouldStop = YES;
            NSError *err = [NSError errorWithDomain:@"StreamPlayer"
                                               code:ret
                                           userInfo:@{NSLocalizedDescriptionKey: @"Too many decode errors"}];
            [self performSelectorOnMainThread:@selector(notifyDelegateOfFailure:)
                                   withObject:err
                                waitUntilDone:NO];
        }
        return;
    }

    while (ret >= 0) {
        ret = avcodec_receive_frame(codecCtx, frame);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
            break;
        }
        if (ret < 0) {
            _decodeErrorCount++;
            if (_decodeErrorCount > 10) {
                _shouldStop = YES;
                if (_delegate != nil && [_delegate respondsToSelector:@selector(streamPlayer:didFailWithError:)]) {
                    NSError *err = [NSError errorWithDomain:@"StreamPlayer"
                                                       code:ret
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Too many decode errors"}];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self->_delegate streamPlayer:self didFailWithError:err];
                    });
                }
            }
            break;
        }

        if (!frame || frame->nb_samples <= 0) {
            continue;
        }

        // Calculate output size
        int outSamples = frame->nb_samples;
        int outBytes = av_samples_get_buffer_size(NULL, 2, outSamples, AV_SAMPLE_FMT_S16, 1);
        if (outBytes <= 0) {
            continue;
        }

        // Ensure buffer is large enough
        if (_audioBufferSize < outBytes) {
            if (_audioBuffer) {
                free(_audioBuffer);
            }
            _audioBuffer = malloc(outBytes);
            if (_audioBuffer) {
                _audioBufferSize = outBytes;
            } else {
                _audioBufferSize = 0;
                continue;
            }
        }

        uint8_t *outPtrs[] = { (uint8_t *)_audioBuffer };

        int convertedSamples = swr_convert(swrCtx, outPtrs, outSamples,
                                           (const uint8_t **)frame->data, outSamples);
        if (convertedSamples <= 0) {
            continue;
        }

        // Apply volume
        int16_t *samples = (int16_t *)_audioBuffer;
        int sampleCount = convertedSamples * 2;  // stereo

        float effectiveVolume = _muted ? 0.0f : _volume;

        for (int i = 0; i < sampleCount; i++) {
            samples[i] = (int16_t)(samples[i] * effectiveVolume);
        }

        // Play audio via libao
        ao_play(aoDev, (char *)_audioBuffer, convertedSamples * 2 * (int)sizeof(int16_t));
    }
}

#pragma mark - Delegate Helpers

- (void)notifyDelegateOfFailure:(NSError *)err
{
    if (_delegate != nil && [_delegate respondsToSelector:@selector(streamPlayer:didFailWithError:)]) {
        [_delegate streamPlayer:self didFailWithError:err];
    }
}

@end
