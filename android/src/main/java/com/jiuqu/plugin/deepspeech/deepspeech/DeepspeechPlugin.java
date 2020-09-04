package com.jiuqu.plugin.deepspeech.deepspeech;

import androidx.annotation.NonNull;
import android.app.Activity;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;

import org.json.JSONException;
import org.json.JSONObject;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.ByteBuffer;
import java.util.Collection;
import java.util.Map;
import java.util.HashMap;

import java.nio.ByteOrder;
import java.util.Arrays;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import android.util.Log;

import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.content.Context;

/** DeepspeechPlugin */
public class DeepspeechPlugin implements FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler , ActivityAware{

  static {
    System.loadLibrary("cpp");
    System.loadLibrary("deepspeech");
  }

  public static native int WavToMp3(String wav, String mp3, int bitrate);

  public static native int NcreateModel(String filename);
  public static native int NcreateStream(int modelIndex);
  public static native void NfeedAudioContent(int streamIndex,short[] data);
  public static native int NcalculateDB(short[] data);
  public static native String NintermediateDecode(int streamIndex,boolean withMetadata);
  public static native String NfinishStream(int streamIndex,boolean withMetadata);
  public static native void NfreeStream(int streamIndex);
  
  public static native String NgetLastError();
  public static native String NspeechToText(int modelIndex,short[] data,boolean withMetadata);
  public static native void NresetError();
  
  public static native void NfreeModel(int modelIndex);
  public static native void NsetScorer(int modelIndex,String scorerPath,double alpha,double beta);
  public static native int NgetSampleRate(int modelIndex);
  private static final String TAG = "DeepspeechPlugin";
  private String TFLITE_MODEL_FILENAME = "deepspeech-0.8.0-models.tflite";
  private String SCORER_FILENAME = "today_is_different.scorer";
  private int streamIndex = -1;
  private int cap_id = -1;
  private boolean isRecording = false;;
  private AudioRecord recorder = null;
  private String tmpFile;
  private String outFile;
  public Context context;
  public Activity activity;
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private MethodChannel methodChannel;
  private EventChannel eventChannel;
  private EventChannel.EventSink eventSink;

  private static byte[] shortToBytes(short[] shorts) {
		if(shorts==null){
			return null;
		}
		byte[] bytes = new byte[shorts.length * 2];
		ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().put(shorts);
		
	    return bytes;
	}	
  
  @Override
  public void onListen(Object o, EventChannel.EventSink sink) {
      eventSink = sink;
      Log.e(TAG, "onListen ");
  }

  @Override
  public void onCancel(Object o) {
      eventSink = null;
       Log.e(TAG, "onCancel ");
  }
  private void sendEvent(final Map<String, Object> params) {
        
       
        this.activity.runOnUiThread(new Runnable() {
                        public void run() {
                            if (eventSink != null) {
                                eventSink.success(params);
                            }
                            Log.e(TAG, "sendEvent ");
                        }
        });
       
  }
  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    this.activity = binding.getActivity();
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    this.activity = null;
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
    this.activity = binding.getActivity();
  }

  @Override
  public void onDetachedFromActivity() {
    this.activity = null;
  }

  public void startSpeech(int modelIndex,final boolean withMetadata)
  {
    String documentDirectoryPath = this.context.getFilesDir().getAbsolutePath();
    outFile = documentDirectoryPath + "/" + "audio.wav";
    tmpFile = documentDirectoryPath + "/" + "temp.pcm";
    
    final int rate = DeepspeechPlugin.NgetSampleRate(modelIndex);
    streamIndex = DeepspeechPlugin.NcreateStream(modelIndex);
    recorder = new AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                rate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                1024 * 2);
    recorder.startRecording();
    isRecording  = true;
    new Thread(new Runnable() {
        @Override
        public void run() {
            try {
                FileOutputStream os = new FileOutputStream(tmpFile);
                short[] audioData = new short[1024];
                while (isRecording) {
                    recorder.read(
                        audioData,
                        0,
                        1024
                    );
                    os.write(shortToBytes(audioData), 0, 1024*2);
                    DeepspeechPlugin.NfeedAudioContent(streamIndex,audioData);
                    String text =  DeepspeechPlugin.NintermediateDecode(streamIndex,withMetadata);

                    int db = DeepspeechPlugin.NcalculateDB(audioData);
                    Map<String, Object> params = new HashMap<>();
                    params.put("ret", text);
                    params.put("vad",db);
                    sendEvent(params);

                }
                String text =  DeepspeechPlugin.NfinishStream(streamIndex,withMetadata);
                if(recorder != null)
                    recorder.stop();
                recorder = null;
                os.close();
                saveAsWav(rate);
                Map<String, Object> params = new HashMap<>();
                params.put("ret", text);
                params.put("vad",0);
                params.put("stop",1);
                sendEvent(params);
            } catch (Exception e) {
                e.printStackTrace();
            }
            
        }
    }).start();
  }
  private static void copyAssetsToDst(Context context,String srcPath,String dstPath,boolean force) 
  {
    Log.e(TAG, "copyAssetsToDst " + srcPath + "->" + dstPath);
      try {
          String fileNames[] =context.getAssets().list(srcPath);
          if (fileNames.length > 0)
          {
              File file = new File(dstPath);
              file.mkdirs();
              for (String fileName : fileNames)
              {
                  if(srcPath.isEmpty())
                  {
                      copyAssetsToDst(context, fileName, dstPath+"/"+fileName,force);
                  }
                  else
                  {
                      copyAssetsToDst(context,srcPath + "/" + fileName, dstPath+"/"+fileName,force);
                  }
              }
          }
          else
          {
              File dstFile = new File(dstPath);
              if(dstFile.exists() && !force){
                    Log.e(TAG, "skip file " + dstPath);
                    return;
                }
              InputStream is = context.getAssets().open(srcPath);
              FileOutputStream fos = new FileOutputStream(dstFile);
              byte[] buffer = new byte[1024];
              int byteCount=0;
              while((byteCount=is.read(buffer))!=-1) {
                  fos.write(buffer, 0, byteCount);
              }
              fos.flush();//刷新缓冲区
              is.close();
              fos.close();
          }
      } catch (Exception e) {
          // TODO Auto-generated catch block
          e.printStackTrace();
          Log.e(TAG, "copyAssetsToDst exception " + srcPath + "->" + dstPath, e);
      }
    }
  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {

    BinaryMessenger messenger = flutterPluginBinding.getBinaryMessenger();
    methodChannel = new MethodChannel(messenger, "deepspeech");
    methodChannel.setMethodCallHandler(this);

    eventChannel = new EventChannel(messenger, "event/deepspeech");
    eventChannel.setStreamHandler(this);

    this.context = flutterPluginBinding.getApplicationContext();
    
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    switch (call.method) {
      case "createModel": {
        String path = call.argument("path");
        int ret = DeepspeechPlugin.NcreateModel(path);
        result.success(ret);
        break;
      }
      case "freeModel": {
        int modelIndex = call.argument("modelIndex");
        DeepspeechPlugin.NfreeModel(modelIndex);
        break;
      }
      case "setScorer": {
        int modelIndex = call.argument("modelIndex");
        String path = call.argument("path");
        double alpha = call.argument("alpha");
        double beta = call.argument("beta");
        DeepspeechPlugin.NsetScorer(modelIndex,path,alpha,beta);
        break;
      } 
      case "startSpeech": {
        int modelIndex = call.argument("modelIndex");
        boolean withMetadata = call.argument("withMetadata");

        this.startSpeech(modelIndex, withMetadata);
        result.success(outFile);
        break;
      }
      case "stopSpeech": {
        isRecording = false;
        break;
      } 
      case "getLastError": {
        result.success(DeepspeechPlugin.NgetLastError());
        break;
      } 
      case "resetError": {
        DeepspeechPlugin.NresetError();
        break;
      }
      case "copyAssetsToDst": {
        final String srcPath = call.argument("srcPath");
        final String dstPath = call.argument("dstPath");
        boolean asyn = call.argument("asyn");
        final boolean force = call.argument("force");
        final Context _context = this.context;
        if(asyn)
        {
          new Thread(new Runnable() {
            @Override
            public void run() {
              DeepspeechPlugin.copyAssetsToDst(_context, srcPath, dstPath,force);
            }
          }).start();
        }
        else
          DeepspeechPlugin.copyAssetsToDst(_context, srcPath, dstPath,force);

        break;  
      }             
      default:
        result.notImplemented();
      break;
    }

  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    methodChannel.setMethodCallHandler(null);
  }

  private void saveAsWav(int rate) {
        try {
            FileInputStream in = new FileInputStream(tmpFile);
            FileOutputStream out = new FileOutputStream(outFile);
            long totalAudioLen = in.getChannel().size();;
            long totalDataLen = totalAudioLen + 36;

            addWavHeader(rate,out, totalAudioLen, totalDataLen);

            byte[] data = new byte[1024];
            int bytesRead;
            while ((bytesRead = in.read(data)) != -1) {
                out.write(data, 0, bytesRead);
            }
            Log.e(TAG, "file path:" + outFile);
            Log.e(TAG, "file size:" + out.getChannel().size());

            in.close();
            out.close();
            deleteTempFile();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void addWavHeader(int rate,FileOutputStream out, long totalAudioLen, long totalDataLen)
            throws Exception {

        long sampleRate = rate;
        int channels = 1;
        int bitsPerSample = 16;
        long byteRate =  sampleRate * channels * bitsPerSample / 8;
        int blockAlign = channels * bitsPerSample / 8;

        byte[] header = new byte[44];

        header[0] = 'R';                                    // RIFF chunk
        header[1] = 'I';
        header[2] = 'F';
        header[3] = 'F';
        header[4] = (byte) (totalDataLen & 0xff);           // how big is the rest of this file
        header[5] = (byte) ((totalDataLen >> 8) & 0xff);
        header[6] = (byte) ((totalDataLen >> 16) & 0xff);
        header[7] = (byte) ((totalDataLen >> 24) & 0xff);
        header[8] = 'W';                                    // WAVE chunk
        header[9] = 'A';
        header[10] = 'V';
        header[11] = 'E';
        header[12] = 'f';                                   // 'fmt ' chunk
        header[13] = 'm';
        header[14] = 't';
        header[15] = ' ';
        header[16] = 16;                                    // 4 bytes: size of 'fmt ' chunk
        header[17] = 0;
        header[18] = 0;
        header[19] = 0;
        header[20] = 1;                                     // format = 1 for PCM
        header[21] = 0;
        header[22] = (byte) channels;                       // mono or stereo
        header[23] = 0;
        header[24] = (byte) (sampleRate & 0xff);            // samples per second
        header[25] = (byte) ((sampleRate >> 8) & 0xff);
        header[26] = (byte) ((sampleRate >> 16) & 0xff);
        header[27] = (byte) ((sampleRate >> 24) & 0xff);
        header[28] = (byte) (byteRate & 0xff);              // bytes per second
        header[29] = (byte) ((byteRate >> 8) & 0xff);
        header[30] = (byte) ((byteRate >> 16) & 0xff);
        header[31] = (byte) ((byteRate >> 24) & 0xff);
        header[32] = (byte) blockAlign;                     // bytes in one sample, for all channels
        header[33] = 0;
        header[34] = (byte) bitsPerSample;                  // bits in a sample
        header[35] = 0;
        header[36] = 'd';                                   // beginning of the data chunk
        header[37] = 'a';
        header[38] = 't';
        header[39] = 'a';
        header[40] = (byte) (totalAudioLen & 0xff);         // how big is this data chunk
        header[41] = (byte) ((totalAudioLen >> 8) & 0xff);
        header[42] = (byte) ((totalAudioLen >> 16) & 0xff);
        header[43] = (byte) ((totalAudioLen >> 24) & 0xff);

        out.write(header, 0, 44);
    }

    private void deleteTempFile() {
        File file = new File(tmpFile);
        file.delete();
    }

}
