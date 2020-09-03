#import "DeepspeechPlugin.h"
#import "deepspeech.h"

#import "DeepSpeechHelper.h"

#import <map>
#import <string>
#import <vector>

using namespace std;

@implementation DeepspeechPlugin

static map<int,ModelState*> s_mapModel;
static int modelIndex = 0;
static map<int,StreamingState*> s_mapStream;
static int s_streamIndex = 0;
const int json_candidate_transcripts = 3;
static string s_lastError;

static void HandleInputBuffer(void *inUserData,
AudioQueueRef inAQ,
AudioQueueBufferRef inBuffer,
const AudioTimeStamp *inStartTime,
UInt32 inNumPackets,
const AudioStreamPacketDescription *inPacketDesc) {
  
  AQRecordState* pRecordState = (AQRecordState *)inUserData;
  
  if (!pRecordState->mIsRunning) {
      return;
  }
  
  if (AudioFileWritePackets(pRecordState->mAudioFile,
                            false,
                            inBuffer->mAudioDataByteSize,
                            inPacketDesc,
                            pRecordState->mCurrentPacket,
                            &inNumPackets,
                            inBuffer->mAudioData
                            ) == noErr) {
      pRecordState->mCurrentPacket += inNumPackets;
  }
  
  short *samples = (short *) inBuffer->mAudioData;
  long nsamples = inBuffer->mAudioDataByteSize / 2;
  StreamingState* stream = s_mapStream[pRecordState->mStreamIndex];
  DS_FeedAudioContent(stream,samples,(unsigned int)nsamples);
  string text;
  if(pRecordState->mWithMetadata)
  {
      Metadata* ret = DS_IntermediateDecodeWithMetadata(stream,json_candidate_transcripts);
      if(ret)
      {
          text = MetadataToJSON(ret);
          DS_FreeMetadata(ret);
      }
  }
  else
  {
      char* ret = DS_IntermediateDecode(stream);
      
      if(ret)
      {
          text = ret;
          DS_FreeString(ret);
      }
  }
  [pRecordState->mSelf sendEventToFlutter:@{@"ret":[NSString stringWithUTF8String:text.c_str()] }];
  AudioQueueEnqueueBuffer(pRecordState->mQueue, inBuffer, 0, NULL);
  
}
- (void)initRecordState:(NSDictionary *)options
{
    _recordState.mDataFormat.mSampleRate        = options[@"sampleRate"] == nil ? 16000 : [options[@"sampleRate"] doubleValue];
    _recordState.mDataFormat.mBitsPerChannel    = options[@"bitsPerSample"] == nil ? 16 : [options[@"bitsPerSample"] unsignedIntValue];
    _recordState.mDataFormat.mChannelsPerFrame  = options[@"channels"] == nil ? 1 : [options[@"channels"] unsignedIntValue];
    _recordState.mDataFormat.mBytesPerPacket    = (_recordState.mDataFormat.mBitsPerChannel / 8) * _recordState.mDataFormat.mChannelsPerFrame;
    _recordState.mDataFormat.mBytesPerFrame     = _recordState.mDataFormat.mBytesPerPacket;
    _recordState.mDataFormat.mFramesPerPacket   = 1;
    _recordState.mDataFormat.mReserved          = 0;
    _recordState.mDataFormat.mFormatID          = kAudioFormatLinearPCM;
    _recordState.mDataFormat.mFormatFlags       = _recordState.mDataFormat.mBitsPerChannel == 8 ? kLinearPCMFormatFlagIsPacked : (kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked);

    
    _recordState.bufferByteSize = 2048;
    _recordState.mSelf = self;
    
    NSString *fileName = options[@"wavFile"] == nil ? @"audio.wav" : options[@"wavFile"];
    NSString *docDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    _filePath = [NSString stringWithFormat:@"%@/%@", docDir, fileName];
}

extern "C" int WavToMp3(const char* wavPath, const char* mp3Path, int bitrate);


- (int)wav2Mp3:(NSString*)wav
                  mp3:(NSString*)mp3
                  bitrate:(int) bitrate
{
    int ret = WavToMp3([wav UTF8String], [mp3 UTF8String], bitrate);
    return ret;
}
- (int)createModel:(NSString*)path
{
  NSString *newPath = path;
  if(![path isAbsolutePath])
    newPath=[[NSBundle mainBundle] pathForResource:path ofType:nil];
  
  
  string pathKey = [newPath UTF8String];
  ModelState* ctx;
  int status = DS_CreateModel(pathKey.c_str(), &ctx);
  if (status != 0) {
    char* error = DS_ErrorCodeToErrorMessage(status);
    if(error)
      s_lastError = error;
    free(error);
    return 0;
  }
  else
  {
    s_mapModel[++modelIndex] = ctx;
    return modelIndex;
  }
}
- (void)freeModel:(int)index
{
  if(s_mapModel.find(index) == s_mapModel.end())
  {
    s_lastError = "can not find model";
  }
  else
  {
      ModelState* ctx = s_mapModel[index];
      DS_FreeModel(ctx);
      s_mapModel.erase(modelIndex);
  }
}

- (void)setScorer:(int)index
              path:(NSString*)path
              alpha:(double)alpha
              beat:(double)beta
{
   if(s_mapModel.find(index) == s_mapModel.end())
   {
     s_lastError = "can not find model";
   }
   else
   {
     ModelState* ctx = s_mapModel[index];
     if([path isEqual:@""])
     {
       int status = DS_DisableExternalScorer(ctx);
       if (status != 0)
         s_lastError = "Could not disable external scorer.\n";
     }
     else
     {
       NSString *newPath = path;
       if(![path isAbsolutePath])
         newPath=[[NSBundle mainBundle] pathForResource:path ofType:nil];
          
       string pathKey = [newPath UTF8String];
       int status = DS_EnableExternalScorer(ctx,pathKey.c_str());
       if (status != 0)
         s_lastError = "Could not enable external scorer.\n";
       else
       {
         if (alpha > 0.001 && beta > 0.001) {
           status = DS_SetScorerAlphaBeta(ctx, alpha, beta);
           if (status != 0) {
             s_lastError = "Error setting scorer alpha and beta.\n";
           }
         }
       }
     }
   }
}

- (void)startSpeech:(int)modeIndex
          withMetadata:(BOOL)withMetadata
{
  if(s_mapModel.find(modeIndex) == s_mapModel.end())
  {
    s_lastError = "can not find model";
  }
  else
  {
    ModelState* aCtx = s_mapModel[modeIndex];
    StreamingState* ctx;
    int status = DS_CreateStream(aCtx, &ctx);
    if (status != DS_ERR_OK) {
      s_lastError = "can not create stream";
    }
    s_mapStream[++s_streamIndex] = ctx;
    
    _recordState.mStreamIndex = s_streamIndex;
    _recordState.mWithMetadata = withMetadata;
    
    int rate = DS_GetModelSampleRate(aCtx);
    NSDictionary *dic =@{@"sampleRate":[NSString stringWithFormat:@"%d",rate]};
    
    [self initRecordState:dic];
  
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryRecord error:nil];

    _recordState.mIsRunning = true;
    _recordState.mCurrentPacket = 0;
    
    CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)_filePath, NULL);
    AudioFileCreateWithURL(url, kAudioFileWAVEType, &_recordState.mDataFormat, kAudioFileFlags_EraseFile, &_recordState.mAudioFile);
    CFRelease(url);
    _recordState.mSelf = self;
    AudioQueueNewInput(&_recordState.mDataFormat, HandleInputBuffer, &_recordState, NULL, NULL, 0, &_recordState.mQueue);
    for (int i = 0; i < kNumberBuffers; i++) {
        AudioQueueAllocateBuffer(_recordState.mQueue, _recordState.bufferByteSize, &_recordState.mBuffers[i]);
        AudioQueueEnqueueBuffer(_recordState.mQueue, _recordState.mBuffers[i], 0, NULL);
    }
    AudioQueueStart(_recordState.mQueue, NULL);
  }
}

- (NSString*)stopSpeech:(BOOL)withMetadata
{
  if (_recordState.mIsRunning) {
      _recordState.mIsRunning = false;
      AudioQueueStop(_recordState.mQueue, true);
      AudioQueueDispose(_recordState.mQueue, true);
      AudioFileClose(_recordState.mAudioFile);
    
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];

  }
  
  StreamingState* stream = s_mapStream[_recordState.mStreamIndex];
  string text;
  if(withMetadata)
  {
      Metadata* ret = DS_FinishStreamWithMetadata(stream,json_candidate_transcripts);
      if(ret)
      {
          text = MetadataToJSON(ret);
          DS_FreeMetadata(ret);
      }
  }
  else
  {
      char* ret = DS_FinishStream(stream);
      if(ret)
      {
          text = ret;
          DS_FreeString(ret);
      }
  }

  return [NSString stringWithUTF8String:text.c_str()];
}

- (NSString*)getLastError{
  return [NSString stringWithUTF8String:s_lastError.c_str()];
}
- (void)resetError{
  s_lastError = "no error";
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"deepspeech"
            binaryMessenger:[registrar messenger]];
  
  DeepspeechPlugin* instance = [[DeepspeechPlugin alloc] init];
  [instance createEventChannel:[registrar messenger]];
  [registrar addMethodCallDelegate:instance channel:channel];
}
-(void) createEventChannel:(NSObject<FlutterBinaryMessenger>*)messenger
{
  _eventChannel = [FlutterEventChannel eventChannelWithName:@"event/deepspeech" binaryMessenger:messenger];
  [_eventChannel setStreamHandler:self];
}
-(void) sendEventToFlutter:(id _Nullable) event
{
  if(self.eventSink)
  {
    self.eventSink(event);
  }
}
- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSDictionary *args = call.arguments;
  if([@"wav2Mp3" isEqualToString:call.method])
  {
    NSString* wav = [args objectForKey:@"wav"];
    NSString* mp3 = [args objectForKey:@"mp3"];
    int bitrate = [[args valueForKey:@"bitrate"] intValue];

    int index = [self wav2Mp3:wav mp3:mp3 bitrate:bitrate];
    result(@(index));
  }
  else if([@"createModel" isEqualToString:call.method])
  {
    NSString* path = [args objectForKey:@"path"];
    int index = [self createModel:path];
    result(@(index));
  }
  else if([@"freeModel" isEqualToString:call.method])
  {
    int modelIndex = [[args valueForKey:@"modelIndex"] intValue];
    [self freeModel:modelIndex];
    
  }
  else if([@"setScorer" isEqualToString:call.method])
  {
    int modelIndex = [[args valueForKey:@"modelIndex"] intValue];
    NSString* path = [args objectForKey:@"path"];
    double alpha = [[args valueForKey:@"alpha"] doubleValue];
    double beta = [[args valueForKey:@"beta"] doubleValue];
    
    [self setScorer:modelIndex path:path alpha:alpha beat:beta];
  }
  else if([@"startSpeech" isEqualToString:call.method])
  {
    int modelIndex = [[args valueForKey:@"modelIndex"] intValue];
    BOOL withMetadata = [[args valueForKey:@"withMetadata"] boolValue];
    dispatch_async(dispatch_get_main_queue(), ^{
         [self startSpeech:modelIndex withMetadata:withMetadata];
    });
   
  }
  else if([@"stopSpeech" isEqualToString:call.method])
  {
    BOOL withMetadata = [[args valueForKey:@"withMetadata"] boolValue];
    dispatch_async(dispatch_get_main_queue(), ^{
         NSString* ret = [self stopSpeech:withMetadata];
         result(ret);
    });
    
  }
  else if([@"getLastError" isEqualToString:call.method])
  {
    NSString* ret = [self getLastError];
    result(ret);
  }
  else if([@"resetError" isEqualToString:call.method])
  {
    [self resetError];
  }
  else {
    result(FlutterMethodNotImplemented);
  }
}

- (FlutterError* _Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(FlutterEventSink)eventSink{
    self.eventSink = eventSink;
    return nil;
}
 
- (FlutterError* _Nullable)onCancelWithArguments:(id _Nullable)arguments {
    return nil;
}
@end
