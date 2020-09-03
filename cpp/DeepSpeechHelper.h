#pragma onece

#include <map>
#include <string>
#include <vector>
#include <sstream>
#include "deepspeech.h"
using namespace std;

string
MetadataToJSON(Metadata* result);
int pcm_db_count(const unsigned char* ptr, size_t size);
