
import 'dart:async';

import 'package:flutter/services.dart';

class Deepspeech {
  static const MethodChannel methodChannel =
      const MethodChannel('deepspeech');
  static const EventChannel eventChannel = 
      const EventChannel('event/deepspeech');
  
  static Future<String> get platformVersion async {
    final String version = await methodChannel.invokeMethod('getPlatformVersion',{"test":"sssss"});
    return version;
  }

  static Future<int>  createModel(String path) async {
    final int index = await methodChannel.invokeMethod('createModel',{"path":path});
    return index;
  }

  static Future<void>  setScorer(int modelIndex,String path,double alpha,double beta) async {
    await methodChannel.invokeMethod('setScorer',{"modelIndex":modelIndex,"path":path,"alpha":alpha,"beta":beta});
  }
  static Future<String>  getLastError() async {
    return await methodChannel.invokeMethod('getLastError');
  }
  static Future<void>  resetError() async {
    await methodChannel.invokeMethod('resetError');
  }
  static Future<void>  startSpeech(int modelIndex,bool withMetadata,_onEvent,_onError) async {
    eventChannel.receiveBroadcastStream().listen(_onEvent, onError: _onError);
    await methodChannel.invokeMethod('startSpeech',{"modelIndex":modelIndex,"withMetadata":withMetadata});


  }
  static Future<String>  stopSpeech(bool withMetadata) async {
    return await methodChannel.invokeMethod('stopSpeech',{"withMetadata":withMetadata});
  }
}
