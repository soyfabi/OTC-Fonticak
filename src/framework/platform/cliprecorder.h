#pragma once

#ifdef WIN32

#include <string>

class ClipRecorder
{
public:
    void configure(void* window, std::string writeDir, int framesPerSecond, int bufferMinutes,
                   int resolution = 0, int quality = 1, bool automaticEncoder = true);
    void configureFromGame(bool enabled, int framesPerSecond, int bufferMinutes,
                           int resolution, int quality, bool automaticEncoder);
    bool save(int format);
    bool isRecording();
    std::string status();
    void shutdown();
};

extern ClipRecorder g_clipRecorder;

#endif
