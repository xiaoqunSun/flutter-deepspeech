#import <Flutter/Flutter.h>
#import <AVFoundation/AVFoundation.h>

#define kNumberBuffers 3

typedef struct {
    __unsafe_unretained id      mSelf;
    AudioStreamBasicDescription mDataFormat;
    AudioQueueRef               mQueue;
    AudioQueueBufferRef         mBuffers[kNumberBuffers];
    AudioFileID                 mAudioFile;
    UInt32                      bufferByteSize;
    SInt64                      mCurrentPacket;
    bool                        mIsRunning;
    int                         mStreamIndex;
    bool                        mWithMetadata;
} AQRecordState;

@interface DeepspeechPlugin : NSObject<FlutterPlugin,FlutterStreamHandler>
@property (nonatomic, assign) AQRecordState recordState;
@property (nonatomic, strong) NSString* filePath;
@property (nonatomic, assign) FlutterEventChannel* eventChannel;
@property (nonatomic, strong) FlutterEventSink eventSink;
-(void) createEventChannel:(NSObject<FlutterBinaryMessenger>*)messenger;
-(void) sendEventToFlutter:(id _Nullable)event;
@end
