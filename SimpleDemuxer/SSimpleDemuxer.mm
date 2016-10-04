//
//  SSimpleDemuxer.m
//  SimpleDemuxer
//
//  Created by yinggeli on 16/10/4.
//  Copyright © 2016年 LYG. All rights reserved.
//

#import "SSimpleDemuxer.h"

extern "C"{
    #include <libavcodec/avcodec.h>
    #include <libavformat/avformat.h>
    #include <libavcodec/put_bits.h>
}



typedef struct ADTSContext
{
    int write_adts;
    int objecttype;
    int sample_rate_index;
    int channel_conf;
} *tt;

#define ADTS_HEADER_SIZE 7/*ADTS 头中相对有用的信息 采样率、声道数、帧长度。想想也是，我要是解码器的话，你给我一堆得AAC音频ES流我也解不出来。每一个带ADTS头信息的AAC流会清晰的告送解码器他需要的这些信息。*/

#define TEST_H264  1


@implementation SSimpleDemuxer


int ff_adts_write_frame_header(ADTSContext *ctx,
                               uint8_t *buf, int size, int pce_size)
{
    PutBitContext pb;
    
    init_put_bits(&pb, buf, ADTS_HEADER_SIZE);
    
    /* adts_fixed_header */
    put_bits(&pb, 12, 0xfff);   /* syncword */
    put_bits(&pb, 1, 0);        /* ID */
    put_bits(&pb, 2, 0);        /* layer */
    put_bits(&pb, 1, 1);        /* protection_absent */
    put_bits(&pb, 2, ctx->objecttype); /* profile_objecttype */
    put_bits(&pb, 4, ctx->sample_rate_index);
    put_bits(&pb, 1, 0);        /* private_bit */
    put_bits(&pb, 3, ctx->channel_conf); /* channel_configuration */
    put_bits(&pb, 1, 0);        /* original_copy */
    put_bits(&pb, 1, 0);        /* home */
    
    /* adts_variable_header */
    put_bits(&pb, 1, 0);        /* copyright_identification_bit */
    put_bits(&pb, 1, 0);        /* copyright_identification_start */
    put_bits(&pb, 13, ADTS_HEADER_SIZE + size + pce_size); /* aac_frame_length */
    put_bits(&pb, 11, 0x7ff);   /* adts_buffer_fullness 0x7ff说明时可变码率 */
    put_bits(&pb, 2, 0);        /* number_of_raw_data_blocks_in_frame */
    
    flush_put_bits(&pb);
    
    return 0;
}


/*
 简单介绍一下流程中各个重要函数的意义：
 avformat_open_input()：打开输入文件。
 av_read_frame()：获取一个AVPacket。
 fwrite()：根据得到的AVPacket的类型不同，分别写入到不同的文件中。
 
 把av_bitstream_filter_filter()的输入数据和输出数据（分别对应第4,5,6,7个参数）都设置成AVPacket的data字段就可以了。
 需要注意的是bitstream filter需要初始化和销毁，分别通过函数av_bitstream_filter_init()和av_bitstream_filter_close()。
 经过上述代码处理之后，AVPacket中的数据有如下变化：
 *每个AVPacket的data添加了H.264的NALU的起始码{0,0,0,1}
 *每个IDR帧数据前面添加了SPS和PPS
 */
int doDemuxTest(){
    
    AVFormatContext *ifmt_ctx = NULL;
    AVPacket pkt;
    int ret, i;
    int videoindex=-1,audioindex=-1;
    
    NSString *filepath = [[NSBundle mainBundle]pathForResource:@"aac_h264" ofType:@"mp4"];
    const char *in_filename  = [filepath UTF8String];
    //输出文件 放在沙盒 caches 目录下
    NSArray * documents = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *docementDir = [[documents objectAtIndex:0] stringByAppendingFormat:@"/Caches"];
    const char *out_filename_v = [[NSString stringWithFormat:@"%@/v_output_h264.h264",docementDir] UTF8String];
    const char *out_filename_a = [[NSString stringWithFormat:@"%@/a_output.aac",docementDir] UTF8String];
    
    av_register_all();
    
    if (!in_filename) {
        printf( "Input file is not exist.");
        return -1;
    }
    
    //Input
    if ((ret = avformat_open_input(&ifmt_ctx, in_filename, 0, 0)) < 0) {
        printf( "Could not open input file.");
        return -1;
    }
    
    /* 解析H264  的配置信息 ：
     1. ffmpeg的avformat_find_stream_info函数可以取得音视频媒体多种，比如播放持续时间、音视频压缩格式、音轨信息、字幕信息、帧率、采样率等;
     2. ff_h264_decode_extradata 解析extradata；
     3. 如果音频数据是AAC流，在解码时需要ADTS(Audio Data Transport Stream)头部，不管是容器封装还是流媒体，没有这个，一般都是不能播放的。很多朋友在做AAC流播放时遇到播不出声音，很可能就是这个原因导致。
     
     ADTS所需的数据仍然是放在上面的扩展数据extradata中，我们需要先解码这个扩展数据，然后再从解码后的数据信息里面重新封装成ADTS头信息，加到每一帧AAC数据之前再送解码器，这样就可以正常解码了。*/
    if ((ret = avformat_find_stream_info(ifmt_ctx, 0)) < 0) {
        printf( "Failed to retrieve input stream information");
        return -1;
    }
    
    
    
    videoindex=-1;
    for(i=0; i<ifmt_ctx->nb_streams; i++) {
        if(ifmt_ctx->streams[i]->codec->codec_type==AVMEDIA_TYPE_VIDEO){
            videoindex=i;
        }else if(ifmt_ctx->streams[i]->codec->codec_type==AVMEDIA_TYPE_AUDIO){
            audioindex=i;
        }
    }
    //Dump Format------------------
    printf("\nInput Video===========================\n");
    av_dump_format(ifmt_ctx, 0, in_filename, 0);
    printf("%s",ifmt_ctx);
    printf("\n======================================\n");
    
    FILE *fp_audio=fopen(out_filename_a,"wb+");
    if (NULL == fp_audio) {
        printf( "Could not open audio output file.");
        return -1;
    }
    FILE *fp_video=fopen(out_filename_v,"wb+");
    if (NULL == fp_video) {
        printf( "Could not open video output file.");
        return -1;
    }
    /*
     FIX: H.264 in some container format (FLV, MP4, MKV etc.) need
     "h264_mp4toannexb" bitstream filter (BSF)
     *Add SPS,PPS in front of IDR frame
     *Add start code ("0,0,0,1") in front of NALU
     H.264 in some container (MPEG2TS) don't need this BSF.
     */
#if TEST_H264
    AVBitStreamFilterContext* h264bsfc =  av_bitstream_filter_init("h264_mp4toannexb");//aac_adtstoasc
#endif
    
    /* auto detect the output format from the name. default is mpeg. */
    AVOutputFormat *fmt = av_guess_format(NULL, in_filename, NULL);
    if (!fmt) {
        printf("Could not deduce output format from file extension: using MPEG.\n");
        fmt = av_guess_format("mpeg", NULL, NULL);
    }
    if (!fmt) {
        fprintf(stderr, "Could not find suitable output format\n");
        exit(1);
    }
    
    while(av_read_frame(ifmt_ctx, &pkt)>=0){
        if(pkt.stream_index==videoindex){
            
#if TEST_H264
            av_bitstream_filter_filter(h264bsfc, ifmt_ctx->streams[videoindex]->codec, NULL, &pkt.data, &pkt.size, pkt.data, pkt.size, 0);
#endif
            
            printf("Write Video Packet. size:%d\tpts:%lld\n",pkt.size,pkt.pts);
            fwrite(pkt.data,1,pkt.size,fp_video);
 
        }else if(pkt.stream_index==audioindex){
            
            /*封装前7个字节adts到每一个packet，可以随时解析；  adif只有文件开头有信息，不可以解析每一个packet*/
            if(fmt->audio_codec == AV_CODEC_ID_AAC){

                struct ADTSContext *ctx = (struct ADTSContext*)malloc(sizeof(struct ADTSContext));
                AVCodecContext *codec = ifmt_ctx->streams[audioindex]->codec;
                int sample_rate_index = 0;
                switch (codec->sample_rate) {
                    case 96000:
                        sample_rate_index = 0;
                        break;
                    case 88200:
                        sample_rate_index = 1;
                        break;
                    case 64000:
                        sample_rate_index = 2;
                        break;
                    case 48000:
                        sample_rate_index = 3;
                        break;
                    case 44100:
                        sample_rate_index = 4;
                        break;
                    case 32000:
                        sample_rate_index = 5;
                        break;
                    case 24000:
                        sample_rate_index = 6;
                        break;
                    case 22050:
                        sample_rate_index = 7;
                        break;
                    case 16000:
                        sample_rate_index = 8;
                        break;
                    case 12000:
                        sample_rate_index = 9;
                        break;
                    case 11025:
                        sample_rate_index = 10;
                        break;
                    case 8000:
                        sample_rate_index = 11;
                        break;
                    case 7350:
                        sample_rate_index = 12;
                        break;
                        
                    default:
                        break;
                }
                ctx->sample_rate_index = sample_rate_index;//< samples per second
                ctx->channel_conf = codec->channels;//< number of audio channels
                ctx->objecttype = codec->profile;
                uint8_t buf[ADTS_HEADER_SIZE];
                ff_adts_write_frame_header(ctx,buf, pkt.size, 0);
                fwrite(buf,1,ADTS_HEADER_SIZE,fp_audio);
                free(ctx);
                
                
            }
            printf("Write Audio Packet. size:%d\t pts:%lld\n",pkt.size,pkt.pts);
            fwrite(pkt.data,1,pkt.size,fp_audio);
        }
        
        av_free_packet(&pkt);
    }
    
#if TEST_H264
    av_bitstream_filter_close(h264bsfc);
#endif
    
    fclose(fp_video);
    fclose(fp_audio);
    
    avformat_close_input(&ifmt_ctx);
    
    if (ret < 0 && ret != AVERROR_EOF) {
        printf( "Error occurred.\n");
        return -1;
    }
    return 0;
}

/*
 简单介绍一下流程中各个重要函数的意义：
 avformat_open_input()：打开输入文件。
 avcodec_copy_context()：赋值AVCodecContext的参数。
 avformat_alloc_output_context2()：初始化输出文件。
 avio_open()：打开输出文件。
 avformat_write_header()：写入文件头。
 av_read_frame()：从输入文件读取一个AVPacket。
 av_interleaved_write_frame()：写入一个AVPacket到输出文件。
 av_write_trailer()：写入文件尾。
 */
int doAmendPtsofPacketTest()
{
    AVOutputFormat *ofmt_a = NULL,*ofmt_v = NULL;
    //（Input AVFormatContext and Output AVFormatContext）
    AVFormatContext *ifmt_ctx = NULL, *ofmt_ctx_a = NULL, *ofmt_ctx_v = NULL;
    AVPacket pkt;
    int ret, i;
    int videoindex=-1,audioindex=-1;
    int frame_index=0;
    
    NSString *filepath = [[NSBundle mainBundle]pathForResource:@"mp3_h264" ofType:@"mp4"];
    const char *in_filename  = [filepath UTF8String];
    
    //在沙盒创建测试视频文件的目录
    NSArray * documents = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *docementDir = [[documents objectAtIndex:0] stringByAppendingFormat:@"/Caches"];
    NSString *out_filename = [NSString stringWithFormat:@"%@/v_output_h264.h264",docementDir];
    const char *out_filename_v = [out_filename UTF8String];
    NSString *out_filename1 = [NSString stringWithFormat:@"%@/ainiyiwannian.mp3",docementDir];
    const char *out_filename_a = [out_filename1 UTF8String];
    
    
    
    av_register_all();
    //Input
    if ((ret = avformat_open_input(&ifmt_ctx, in_filename, 0, 0)) < 0) {
        printf( "Could not open input file.");
        goto end;
    }
    if ((ret = avformat_find_stream_info(ifmt_ctx, 0)) < 0) {
        printf( "Failed to retrieve input stream information");
        goto end;
    }
    
    //Output
    avformat_alloc_output_context2(&ofmt_ctx_v, NULL, NULL, out_filename_v);
    if (!ofmt_ctx_v) {
        printf( "Could not create output context\n");
        ret = AVERROR_UNKNOWN;
        goto end;
    }
    ofmt_v = ofmt_ctx_v->oformat;
    
    avformat_alloc_output_context2(&ofmt_ctx_a, NULL, NULL, out_filename_a);
    if (!ofmt_ctx_a) {
        printf( "Could not create output context\n");
        ret = AVERROR_UNKNOWN;
        goto end;
    }
    ofmt_a = ofmt_ctx_a->oformat;
    
    for (i = 0; i < ifmt_ctx->nb_streams; i++) {
        //Create output AVStream according to input AVStream
        AVFormatContext *ofmt_ctx;
        AVStream *in_stream = ifmt_ctx->streams[i];
        AVStream *out_stream = NULL;
        
        if(ifmt_ctx->streams[i]->codec->codec_type==AVMEDIA_TYPE_VIDEO){
            videoindex=i;
            out_stream=avformat_new_stream(ofmt_ctx_v, in_stream->codec->codec);
            ofmt_ctx=ofmt_ctx_v;
        }else if(ifmt_ctx->streams[i]->codec->codec_type==AVMEDIA_TYPE_AUDIO){
            audioindex=i;
            out_stream=avformat_new_stream(ofmt_ctx_a, in_stream->codec->codec);
            ofmt_ctx=ofmt_ctx_a;
        }else{
            break;
        }
        
        if (!out_stream) {
            printf( "Failed allocating output stream\n");
            ret = AVERROR_UNKNOWN;
            goto end;
        }
        //Copy the settings of AVCodecContext
        if (avcodec_copy_context(out_stream->codec, in_stream->codec) < 0) {
            printf( "Failed to copy context from input to output stream codec context\n");
            goto end;
        }
        out_stream->codec->codec_tag = 0;
        
        if (ofmt_ctx->oformat->flags & AVFMT_GLOBALHEADER)
            out_stream->codec->flags |= CODEC_FLAG_GLOBAL_HEADER;
    }
    
    //Dump Format------------------
    printf("\n==============Input Video=============\n");
    av_dump_format(ifmt_ctx, 0, in_filename, 0);
    printf("\n==============Output Video============\n");
    av_dump_format(ofmt_ctx_v, 0, out_filename_v, 1);
    printf("\n==============Output Audio============\n");
    av_dump_format(ofmt_ctx_a, 0, out_filename_a, 1);
    printf("\n======================================\n");
    //Open output file
    if (!(ofmt_v->flags & AVFMT_NOFILE)) {
        if (avio_open(&ofmt_ctx_v->pb, out_filename_v, AVIO_FLAG_WRITE) < 0) {
            printf( "Could not open output file '%s'", out_filename_v);
            goto end;
        }
    }
    
    if (!(ofmt_a->flags & AVFMT_NOFILE)) {
        if (avio_open(&ofmt_ctx_a->pb, out_filename_a, AVIO_FLAG_WRITE) < 0) {
            printf( "Could not open output file '%s'", out_filename_a);
            goto end;
        }
    }
    
    //Write file header
    if (avformat_write_header(ofmt_ctx_v, NULL) < 0) {
        printf( "Error occurred when opening video output file\n");
        goto end;
    }
    if (avformat_write_header(ofmt_ctx_a, NULL) < 0) {
        printf( "Error occurred when opening audio output file\n");
        goto end;
    }
    
#if USE_H264BSF
    AVBitStreamFilterContext* h264bsfc =  av_bitstream_filter_init("h264_mp4toannexb");
#endif
    
    while (1) {
        AVFormatContext *ofmt_ctx;
        AVStream *in_stream, *out_stream;
        //Get an AVPacket
        if (av_read_frame(ifmt_ctx, &pkt) < 0)
            break;
        in_stream  = ifmt_ctx->streams[pkt.stream_index];
        
        
        if(pkt.stream_index==videoindex){
            out_stream = ofmt_ctx_v->streams[0];
            ofmt_ctx=ofmt_ctx_v;
            printf("Write Video Packet. size:%d\tpts:%lld\n",pkt.size,pkt.pts);
#if USE_H264BSF
            av_bitstream_filter_filter(h264bsfc, in_stream->codec, NULL, &pkt.data, &pkt.size, pkt.data, pkt.size, 0);
#endif
        }else if(pkt.stream_index==audioindex){
            out_stream = ofmt_ctx_a->streams[0];
            ofmt_ctx=ofmt_ctx_a;
            printf("Write Audio Packet. size:%d\tpts:%lld\n",pkt.size,pkt.pts);
        }else{
            continue;
        }
        
        
        //Convert PTS/DTS
        pkt.pts = av_rescale_q_rnd(pkt.pts, in_stream->time_base, out_stream->time_base, (AVRounding)(AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX));
        pkt.dts = av_rescale_q_rnd(pkt.dts, in_stream->time_base, out_stream->time_base, (AVRounding)(AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX));
        pkt.duration = av_rescale_q(pkt.duration, in_stream->time_base, out_stream->time_base);
        pkt.pos = -1;
        pkt.stream_index=0;
        printf("Write Packet with scale. size:%d\t pts:%lld\n",pkt.size,pkt.pts);
        
        //Write
        if (av_interleaved_write_frame(ofmt_ctx, &pkt) < 0) {
            printf( "Error muxing packet\n");
            break;
        }
        //printf("Write %8d frames to output file\n",frame_index);
        av_free_packet(&pkt);
        frame_index++;
    }
    
#if USE_H264BSF
    av_bitstream_filter_close(h264bsfc);
#endif
    
    //Write file trailer
    av_write_trailer(ofmt_ctx_a);
    av_write_trailer(ofmt_ctx_v);
end:
    avformat_close_input(&ifmt_ctx);
    /* close output */
    if (ofmt_ctx_a && !(ofmt_a->flags & AVFMT_NOFILE))
        avio_close(ofmt_ctx_a->pb);
    
    if (ofmt_ctx_v && !(ofmt_v->flags & AVFMT_NOFILE))
        avio_close(ofmt_ctx_v->pb);
    
    avformat_free_context(ofmt_ctx_a);
    avformat_free_context(ofmt_ctx_v);
    
    
    if (ret < 0 && ret != AVERROR_EOF) {
        printf( "Error occurred.\n");
        return -1;
    }
    return 0;
}


@end
