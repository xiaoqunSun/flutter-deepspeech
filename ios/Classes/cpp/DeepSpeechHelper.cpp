#include "DeepSpeechHelper.h"
#include <map>
#include <string>
#include <vector>
#include <sstream>
#include "deepspeech.h"
#include "math.h"
using namespace std;

struct meta_word {
  std::string word;
  float start_time;
  float duration;
};
std::vector<meta_word>
CandidateTranscriptToWords(const CandidateTranscript* transcript)
{
  std::vector<meta_word> word_list;

  std::string word = "";
  float word_start_time = 0;

  // Loop through each token
  for (int i = 0; i < transcript->num_tokens; i++) {
    const TokenMetadata& token = transcript->tokens[i];

    // Append token to word if it's not a space
    if (strcmp(token.text, u8" ") != 0) {
      // Log the start time of the new word
      if (word.length() == 0) {
        word_start_time = token.start_time;
      }
      word.append(token.text);
    }

    // Word boundary is either a space or the last token in the array
    if (strcmp(token.text, u8" ") == 0 || i == transcript->num_tokens-1) {
      float word_duration = token.start_time - word_start_time;

      if (word_duration < 0) {
        word_duration = 0;
      }

      meta_word w;
      w.word = word;
      w.start_time = word_start_time;
      w.duration = word_duration;

      word_list.push_back(w);

      // Reset
      word = "";
      word_start_time = 0;
    }
  }

  return word_list;
}


std::string
CandidateTranscriptToJSON(const CandidateTranscript *transcript)
{
  std::ostringstream out_string;

  std::vector<meta_word> words = CandidateTranscriptToWords(transcript);

  out_string << R"("metadata":{"confidence":)" << transcript->confidence << R"(},"words":[)";

  for (int i = 0; i < words.size(); i++) {
    meta_word w = words[i];
    out_string << R"({"word":")" << w.word << R"(","time":)" << w.start_time << R"(,"duration":)" << w.duration << "}";

    if (i < words.size() - 1) {
      out_string << ",";
    }
  }

  out_string << "]";

  return out_string.str();
}

const char*
MetadataToJSON(Metadata* result)
{
  std::ostringstream out_string;
  out_string << "{\n";

  for (int j=0; j < result->num_transcripts; ++j) {
    const CandidateTranscript *transcript = &result->transcripts[j];

    if (j == 0) {
      out_string << CandidateTranscriptToJSON(transcript);

      if (result->num_transcripts > 1) {
        out_string << ",\n" << R"("alternatives")" << ":[\n";
      }
    } else {
      out_string << "{" << CandidateTranscriptToJSON(transcript) << "}";

      if (j < result->num_transcripts - 1) {
        out_string << ",\n";
      } else {
        out_string << "\n]";
      }
    }
  }
  
  out_string << "\n}\n";

  return out_string.str().c_str();
}


int pcm_db_count(const unsigned char* ptr, int size)
{
    int ndb = 0;

    short int value;

    int i;
    long long v = 0;
    for(i=0; i<size; i+=2)
    {
        memcpy((char*)&value, ptr+i, 1);
        memcpy((char*)&value+1, ptr+i+1, 1);
        v += value* value;
    }

    v = v/size;

    ndb = (int)10.0*log10(v);

    return ndb;
}
