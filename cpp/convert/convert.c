#define DR_WAV_IMPLEMENTATION
#include "dr_wav.h"
#include "shine_mp3.h"
int WavToMp3(const char *wavPath, const char *mp3Path, int bitrate)
{
    int ret = 0;
    drwav wav;
#ifdef WIN32
    if (!drwav_init_file_w(&wav, rtc::ToUtf16(wavPath).c_str(), NULL))
#else
    if (!drwav_init_file(&wav, wavPath, NULL))
#endif
    {
        //RTC_LOG_F(WARNING) << "unable to open wavFile " << wavPath;
        return ret;
    }
    FILE *fp = fopen(mp3Path, "wb");
    if (!fp)
    {
        //RTC_LOG_F(WARNING) << "unable to open mp3File " << wavPath;
        drwav_uninit(&wav);
        return ret;
    }
    shine_config_t config;
    shine_set_config_mpeg_defaults(&config.mpeg);
    config.wave.samplerate = wav.sampleRate;
    if (wav.channels > 1)
    {
        config.mpeg.mode = STEREO;
        config.wave.channels = PCM_STEREO;
    }
    else
    {
        config.mpeg.mode = MONO;
        config.wave.channels = PCM_MONO;
    }
    config.mpeg.bitr = bitrate / 1000;
    if (shine_check_config(config.wave.samplerate, config.mpeg.bitr) < 0)
    {
        //RTC_LOG_F(LS_WARNING) << "Unsupported samplerate/bitrate configuration.";
        return 0;
    }
    shine_t enc = shine_initialise(&config);
    int mp3_size, samples_pre_pass = shine_samples_per_pass(enc);
    int16_t *pcm = (int16_t *)malloc(2 * samples_pre_pass * wav.channels);
    while (1)
    {
        int n = drwav_read_pcm_frames_s16(&wav, samples_pre_pass, &pcm[0]);
        if (!n)
            break;
        ret += n;
        uint8_t *mp3_buf = shine_encode_buffer_interleaved(enc, &pcm[0], &mp3_size);
        if (mp3_buf && mp3_size)
        {
            fwrite(mp3_buf, 1, mp3_size, fp);
        }
    }
    free(pcm);
    drwav_uninit(&wav);
    if (enc)
    {
        shine_close(enc);
        enc = NULL;
    }
    if (fp)
    {
        printf("wav2Mp3 %s->%s got %ld mp3\n", wavPath, mp3Path, ftell(fp));
        fclose(fp);
        fp = NULL;
    }
    return ret;
}
