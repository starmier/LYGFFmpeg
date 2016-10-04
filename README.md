# LYGFFmpeg
FFmpeg 详解

功能：一个简单的解复用器；

     a. 支持对 ACC MP3  H264 编码格式的视频进行解复用，并分别将保存到对应的音、视频文件中，文件为可播放文件；
     b. 支持对pts 的修正；
     
使用说明：

     a. 请将 FFmpeg-IOS（可以用你自己编译的替换） 目录放在工程文件同一级目录下；
     b. 导入FFmpeg-IOS 所需要的依赖库：
        AudioToolbox.framework
        VideoToolbox.framework
        CoreMedia.framework
        libbz2.1.0.tbd
        libiconv.2.4.0.tbd
        libz.1.2.5.tbd 
     c. 引入 SSimpleDemuxer.h  SSimpleDemuxer.mm ,在需要调用的.mm 文件中进行生命以下声明，就可以正常使用了：
        int doDemuxTest();
        int doAmendPtsofPacketTest();
         
