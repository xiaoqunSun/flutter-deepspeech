
#include <jni.h>
#include <string>

#include "cpp/DeepSpeechHelper.h"

#include "cpp/deepspeech.h"
#include <map>
#include <string>
#include <vector>

#define CLS_NAME(x) Java_com_jiuqu_plugin_deepspeech_deepspeech_DeepspeechPlugin_##x

using namespace std;
const int json_candidate_transcripts = 3;
static map<int, ModelState *> s_mapModel;
static int s_modelIndex = 0;
static map<int, StreamingState *> s_mapStream;
static int s_streamIndex = 0;

static string s_lastError;
std::string JavaToStdString(JNIEnv *jni, const jstring &j_string)
{
    if (j_string == NULL)
        return std::string();
    const char *chars = jni->GetStringUTFChars(j_string, NULL);
    //CHECK_EXCEPTION(jni) << "Error during GetStringUTFChars";
    std::string str(chars, jni->GetStringUTFLength(j_string));
    //CHECK_EXCEPTION(jni) << "Error during GetStringUTFLength";
    jni->ReleaseStringUTFChars(j_string, chars);
    //CHECK_EXCEPTION(jni) << "Error during ReleaseStringUTFChars";
    return str;
}

extern "C"
{
    int WavToMp3(const char *wavPath, const char *mp3Path, int bitrate);
    jstring stringFromJNI(
        JNIEnv *env,
        std::string text)
    {
        return env->NewStringUTF(text.c_str());
    }
    JNIEXPORT jint JNICALL CLS_NAME(WavToMp3)(JNIEnv *env, jobject obj,
                                             jstring jwav, jstring jmp3, int bitrate)
    {
        std::string wav = JavaToStdString(env, jwav);
        std::string mp3 = JavaToStdString(env, jmp3);
        return WavToMp3(wav.c_str(), mp3.c_str(), bitrate);
    }

    JNIEXPORT jstring JNICALL CLS_NAME(NgetLastError)(JNIEnv *env, jobject)
    {
        return stringFromJNI(env, s_lastError);
    }

    JNIEXPORT void JNICALL CLS_NAME(NresetError)(JNIEnv *env, jobject)
    {
        s_lastError = "no errror";
    }

    JNIEXPORT int JNICALL CLS_NAME(NgetSampleRate)(JNIEnv *env, jobject, int modelIndex)
    {
        if (s_mapModel.find(modelIndex) == s_mapModel.end())
        {
            s_lastError = "can not find model";
            return 0;
        }
        else
        {
            ModelState *ctx = s_mapModel[modelIndex];
            return DS_GetModelSampleRate(ctx);
        }
    }
    JNIEXPORT int JNICALL CLS_NAME(NcreateModel)(JNIEnv *env, jobject, jstring path)
    {

        ModelState *ctx;
        int status = DS_CreateModel(JavaToStdString(env, path).c_str(), &ctx);
        if (status != 0)
        {
            char *error = DS_ErrorCodeToErrorMessage(status);
            if (error)
                s_lastError = error;
            free(error);
            return 0;
        }
        else
        {
            DS_SetModelBeamWidth(ctx, 500);
            s_mapModel[++s_modelIndex] = ctx;
            return s_modelIndex;
        }
    }

    JNIEXPORT void JNICALL CLS_NAME(NfreeModel)(JNIEnv *env, jobject, int modelIndex)
    {

        if (s_mapModel.find(modelIndex) == s_mapModel.end())
        {
            s_lastError = "can not find model";
        }
        else
        {
            ModelState *ctx = s_mapModel[modelIndex];
            DS_FreeModel(ctx);
            s_mapModel.erase(modelIndex);
        }
    }

    JNIEXPORT void JNICALL CLS_NAME(NsetScorer)(JNIEnv *env, jobject, int modelIndex, jstring scorerPath, double alpha, double beta)
    {

        if (s_mapModel.find(modelIndex) == s_mapModel.end())
        {
            s_lastError = "can not find model";
        }
        else
        {
            ModelState *ctx = s_mapModel[modelIndex];
            if (JavaToStdString(env, scorerPath) == "")
            {
                int status = DS_DisableExternalScorer(ctx);
                if (status != 0)
                    s_lastError = "Could not disable external scorer.\n";
            }
            else
            {
                int status = DS_EnableExternalScorer(ctx, JavaToStdString(env, scorerPath).c_str());
                if (status != 0)
                    s_lastError = "Could not enable external scorer.\n";
                else
                {
                    if (alpha > 0.001 && beta > 0.001)
                    {
                        status = DS_SetScorerAlphaBeta(ctx, alpha, beta);
                        if (status != 0)
                        {
                            s_lastError = "Error setting scorer alpha and beta.\n";
                        }
                    }
                }
            }
        }
    }

    JNIEXPORT jstring JNICALL CLS_NAME(NspeechToText)(JNIEnv *env, jobject, int modelIndex, jshortArray data, jboolean withMetadata)
    {

        short *_data = (short *)env->GetShortArrayElements(data, 0);
        int size = env->GetArrayLength(data);
        string text;
        if (s_mapModel.find(modelIndex) == s_mapModel.end())
        {
            s_lastError = "can not find model";
        }
        else
        {
            ModelState *ctx = s_mapModel[modelIndex];
            if (withMetadata)
            {
                Metadata *ret = DS_SpeechToTextWithMetadata(ctx, _data, (unsigned int)size, json_candidate_transcripts);
                if (ret)
                {
                    text = MetadataToJSON(ret);
                    DS_FreeMetadata(ret);
                }
            }
            else
            {
                char *ret = DS_SpeechToText(ctx, _data, (unsigned int)size);
                if (ret)
                {
                    text = ret;
                    DS_FreeString(ret);
                }
            }
        }

        return stringFromJNI(env, text);
    }
    JNIEXPORT int JNICALL CLS_NAME(NcalculateDB)(JNIEnv *env, jobject, jshortArray data)
    {
        short *_data = (short *)env->GetShortArrayElements(data, 0);
        int size = env->GetArrayLength(data);

        return pcm_db_count((const unsigned char *)_data, size * 2);
    }
    JNIEXPORT int JNICALL CLS_NAME(NcreateStream)(JNIEnv *env, jobject, int modelIndex)
    {
        if (s_mapModel.find(modelIndex) == s_mapModel.end())
        {
            s_lastError = "can not find model";
            return 0;
        }
        else
        {
            ModelState *ctx = s_mapModel[modelIndex];
            StreamingState *stream;
            DS_CreateStream(ctx, &stream);
            s_mapStream[++s_streamIndex] = stream;
            return s_streamIndex;
        }
    }
    JNIEXPORT void JNICALL CLS_NAME(NfeedAudioContent)(JNIEnv *env, jobject, int streamIndex, jshortArray data)
    {
        if (s_mapStream.find(streamIndex) == s_mapStream.end())
        {
            s_lastError = "can not find stream";
        }
        else
        {
            StreamingState *stream = s_mapStream[streamIndex];
            short *_data = (short *)env->GetShortArrayElements(data, 0);
            int size = env->GetArrayLength(data);
            DS_FeedAudioContent(stream, _data, (unsigned int)size);
        }
    }

    JNIEXPORT jstring JNICALL CLS_NAME(NintermediateDecode)(JNIEnv *env, jobject, int streamIndex, jboolean withMetadata)
    {
        string text;
        if (s_mapStream.find(streamIndex) == s_mapStream.end())
        {
            s_lastError = "can not find stream";
        }
        else
        {
            StreamingState *stream = s_mapStream[streamIndex];
            if (withMetadata)
            {
                Metadata *ret = DS_IntermediateDecodeWithMetadata(stream, json_candidate_transcripts);
                if (ret)
                {
                    text = MetadataToJSON(ret);
                    DS_FreeMetadata(ret);
                }
            }
            else
            {
                char *ret = DS_IntermediateDecode(stream);
                if (ret)
                {
                    text = ret;
                    DS_FreeString(ret);
                }
            }
        }
        return stringFromJNI(env, text);
    }

    JNIEXPORT jstring JNICALL CLS_NAME(NfinishStream)(JNIEnv *env, jobject, int streamIndex, jboolean withMetadata)
    {
        string text;
        if (s_mapStream.find(streamIndex) == s_mapStream.end())
        {
            s_lastError = "can not find stream";
        }
        else
        {
            StreamingState *stream = s_mapStream[streamIndex];
            if (withMetadata)
            {
                Metadata *ret = DS_FinishStreamWithMetadata(stream, json_candidate_transcripts);
                if (ret)
                {
                    text = MetadataToJSON(ret);
                    DS_FreeMetadata(ret);
                }
            }
            else
            {
                char *ret = DS_FinishStream(stream);
                if (ret)
                {
                    text = ret;
                    DS_FreeString(ret);
                }
            }
        }
        return stringFromJNI(env, text);
    }
    JNIEXPORT void JNICALL CLS_NAME(NfreeStream)(JNIEnv *env, jobject, int streamIndex)
    {
        if (s_mapStream.find(streamIndex) == s_mapStream.end())
        {
            s_lastError = "can not find stream";
        }
        else
        {
            StreamingState *stream = s_mapStream[streamIndex];
            DS_FreeStream(stream);
            s_mapStream.erase(streamIndex);
        }
    }
}