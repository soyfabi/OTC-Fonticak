#ifdef WIN32

#include "cliprecorder.h"
#ifndef NOMINMAX
#define NOMINMAX
#endif
#undef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#undef NTDDI_VERSION
#define NTDDI_VERSION 0x0A000000
#include <Windows.h>
#include <d3d11.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Security.Authorization.AppCapabilityAccess.h>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <thread>
#include <utility>

#ifdef _MSC_VER
#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "windowsapp.lib")
#endif

namespace
{
using namespace winrt;
using namespace winrt::Windows::Graphics;
using namespace winrt::Windows::Graphics::Capture;
using namespace winrt::Windows::Graphics::DirectX;
using namespace winrt::Windows::Graphics::DirectX::Direct3D11;
using namespace std::chrono_literals;

// Media Foundation timestamps use 100 ns units.
constexpr LONGLONG second = 10'000'000;
constexpr LONGLONG segmentDuration = 5 * second;

// Indexed by the saved quality ID. IDs 0, 1 and 2 predate the six-level menu.
constexpr int qualityFactors[]{6, 10, 16, 2, 4, 24};
constexpr int recordingFrameRates[]{15, 20, 24, 30, 60, 80};

struct Settings
{
    HWND window{};
    std::filesystem::path directory;
    int fps{30};
    int minutes{3};
    int resolution{};
    int quality{1};
    bool automaticEncoder{true};

    bool operator==(const Settings&) const = default;
};

const wchar_t* clipExtension(int format)
{
    switch (format) {
        case 1: return L".mkv";
        case 2: return L".avi";
        default: return L".mp4";
    }
}

std::wstring findFfmpeg()
{
    std::wstring executable(32768, L'\0');
    const DWORD length = GetModuleFileNameW(nullptr, executable.data(), static_cast<DWORD>(executable.size()));
    if (length == 0 || length >= executable.size())
        return {};
    executable.resize(length);
    const auto local = std::filesystem::path(executable).parent_path() / L"ffmpeg.exe";
    std::error_code error;
    return std::filesystem::is_regular_file(local, error) ? local.wstring() : std::wstring{};
}

void remuxClip(const std::wstring& ffmpeg, const std::filesystem::path& input, const std::filesystem::path& output)
{
    auto command = L"\"" + ffmpeg + L"\" -nostdin -hide_banner -loglevel error -n -i \"" + input.wstring()
        + L"\" -map 0:v:0 -c:v copy";
    if (output.extension() == L".avi")
        command += L" -bsf:v h264_mp4toannexb";
    command += L" \"" + output.wstring() + L"\"";
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(ffmpeg.c_str(), command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW,
                       nullptr, nullptr, &startup, &process))
        throw std::runtime_error("Could not launch FFmpeg.");
    const winrt::handle child{process.hProcess};
    CloseHandle(process.hThread);
    const auto wait = WaitForSingleObject(child.get(), 30'000);
    DWORD exitCode = 1;
    if (wait == WAIT_OBJECT_0) {
        GetExitCodeProcess(child.get(), &exitCode);
    } else {
        TerminateProcess(child.get(), 1);
        WaitForSingleObject(child.get(), 1000);
    }
    if (exitCode != 0)
        throw std::runtime_error("FFmpeg could not export the selected clip format.");
}

std::wstring uniqueId()
{
    GUID id;
    check_hresult(CoCreateGuid(&id));
    wchar_t formatted[39]{};
    StringFromGUID2(id, formatted, 39);
    return std::wstring(formatted + 1, 36);
}

com_ptr<IMFMediaType> videoType(const GUID& subtype, SizeInt32 size, int fps)
{
    com_ptr<IMFMediaType> type;
    check_hresult(MFCreateMediaType(type.put()));
    check_hresult(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video));
    check_hresult(type->SetGUID(MF_MT_SUBTYPE, subtype));
    check_hresult(MFSetAttributeSize(type.get(), MF_MT_FRAME_SIZE, size.Width, size.Height));
    check_hresult(MFSetAttributeRatio(type.get(), MF_MT_FRAME_RATE, fps, 1));
    check_hresult(MFSetAttributeRatio(type.get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1));
    check_hresult(type->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive));
    return type;
}

com_ptr<IMFSinkWriter> openWriter(const std::filesystem::path& path, IMFMediaType* output,
                                IMFMediaType* input, bool hardware, DWORD& stream)
{
    com_ptr<IMFAttributes> options;
    check_hresult(MFCreateAttributes(options.put(), 1));
    check_hresult(options->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, hardware));
    com_ptr<IMFSinkWriter> writer;
    check_hresult(MFCreateSinkWriterFromURL(path.c_str(), nullptr, options.get(), writer.put()));
    check_hresult(writer->AddStream(output, &stream));
    check_hresult(writer->SetInputMediaType(stream, input, nullptr));
    check_hresult(writer->BeginWriting());
    return writer;
}

struct Capture
{
    void start(HWND window)
    {
        if (!GraphicsCaptureSession::IsSupported())
            throw hresult_error(E_NOTIMPL);

        auto interop = get_activation_factory<GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
        GraphicsCaptureItem item{nullptr};
        check_hresult(interop->CreateForWindow(window, guid_of<GraphicsCaptureItem>(), put_abi(item)));
        size = item.Size();
        check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                                       nullptr, 0, D3D11_SDK_VERSION, device.put(), nullptr, context.put()));
        com_ptr<IInspectable> bridge;
        check_hresult(CreateDirect3D11DeviceFromDXGIDevice(device.as<IDXGIDevice>().get(), bridge.put()));
        directDevice = bridge.as<IDirect3DDevice>();
        pool = Direct3D11CaptureFramePool::CreateFreeThreaded(directDevice, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size);
        session = pool.CreateCaptureSession(item);
        // Windows controls the capture border and can require user consent.
        if (session.try_as<IGraphicsCaptureSession3>()) {
            try {
                borderAccess = GraphicsCaptureAccess::RequestAccessAsync(GraphicsCaptureAccessKind::Borderless);
            } catch (const hresult_error&) {
                // The standalone executable can lack the package capability.
            }
        }
        session.StartCapture();
    }

    ~Capture()
    {
        // The window or device may already be gone. Still close each resource.
        try {
            if (borderAccess)
                borderAccess.Cancel();
        } catch (...) {}
        try {
            if (session)
                session.Close();
        } catch (...) {}
        try {
            if (pool)
                pool.Close();
        } catch (...) {}
    }

    void updateBorder()
    {
        using winrt::Windows::Foundation::AsyncStatus;
        using winrt::Windows::Security::Authorization::AppCapabilityAccess::AppCapabilityAccessStatus;
        if (!borderAccess || borderAccess.Status() == AsyncStatus::Started)
            return;

        auto access = std::exchange(borderAccess, nullptr);
        try {
            if (access.Status() == AsyncStatus::Completed && access.GetResults() == AppCapabilityAccessStatus::Allowed)
                session.as<IGraphicsCaptureSession3>().IsBorderRequired(false);
        } catch (const hresult_error&) {
            // Capture can continue with the system border.
        }
    }

    void resize(SizeInt32 newSize)
    {
        pool.Recreate(directDevice, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, newSize);
        size = newSize;
        staging = nullptr;
    }

    SizeInt32 videoSize(int resolution) const
    {
        if (resolution > 0 && size.Height > resolution)
            return {std::max(2, static_cast<int>(int64_t(size.Width) * resolution / size.Height) & ~1), resolution};
        return {size.Width & ~1, size.Height & ~1};
    }

    com_ptr<IMFSample> copyFrame(const Direct3D11CaptureFrame& frame, SizeInt32 outputSize)
    {
        const auto [width, height] = videoSize(0);
        if (!staging) {
            D3D11_TEXTURE2D_DESC desc{};
            desc.Width = width;
            desc.Height = height;
            desc.MipLevels = 1;
            desc.ArraySize = 1;
            desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
            desc.SampleDesc.Count = 1;
            desc.Usage = D3D11_USAGE_STAGING;
            desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
            check_hresult(device->CreateTexture2D(&desc, nullptr, staging.put()));
        }
        com_ptr<ID3D11Texture2D> texture;
        check_hresult(frame.Surface().as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>()
                          ->GetInterface(IID_PPV_ARGS(texture.put())));
        const D3D11_BOX region{0, 0, 0, static_cast<UINT>(width), static_cast<UINT>(height), 1};
        context->CopySubresourceRegion(staging.get(), 0, 0, 0, 0, texture.get(), 0, &region);

        const auto [outputWidth, outputHeight] = outputSize;
        const DWORD stride = outputWidth * 4;
        com_ptr<IMFMediaBuffer> buffer;
        check_hresult(MFCreateMemoryBuffer(stride * outputHeight, buffer.put()));
        D3D11_MAPPED_SUBRESOURCE mapped{};
        check_hresult(context->Map(staging.get(), 0, D3D11_MAP_READ, 0, &mapped));
        BYTE* bytes{};
        const HRESULT lock = buffer->Lock(&bytes, nullptr, nullptr);
        if (SUCCEEDED(lock)) {
            const auto* pixels = static_cast<const BYTE*>(mapped.pData);
            if (width == outputWidth && height == outputHeight) {
                for (int y = 0; y < height; ++y)
                    std::memcpy(bytes + y * stride, pixels + y * mapped.RowPitch, stride);
            } else {
                for (int y = 0; y < outputHeight; ++y) {
                    const auto* source = reinterpret_cast<const UINT32*>(pixels + (y * height / outputHeight) * mapped.RowPitch);
                    auto* destination = reinterpret_cast<UINT32*>(bytes + y * stride);
                    for (int x = 0; x < outputWidth; ++x)
                        destination[x] = source[x * width / outputWidth];
                }
            }
            buffer->Unlock();
        }
        context->Unmap(staging.get(), 0);
        check_hresult(lock);
        check_hresult(buffer->SetCurrentLength(stride * outputHeight));
        com_ptr<IMFSample> sample;
        check_hresult(MFCreateSample(sample.put()));
        check_hresult(sample->AddBuffer(buffer.get()));
        return sample;
    }

    SizeInt32 size{};
    com_ptr<ID3D11Device> device;
    com_ptr<ID3D11DeviceContext> context;
    com_ptr<ID3D11Texture2D> staging;
    IDirect3DDevice directDevice{nullptr};
    Direct3D11CaptureFramePool pool{nullptr};
    GraphicsCaptureSession session{nullptr};
    winrt::Windows::Foundation::IAsyncOperation<
        winrt::Windows::Security::Authorization::AppCapabilityAccess::AppCapabilityAccessStatus> borderAccess{nullptr};
};

struct BufferDirectory
{
    explicit BufferDirectory(const std::filesystem::path& directory)
        : path(directory / (L".buffer-" + uniqueId()))
    {
        std::filesystem::create_directories(path);
    }

    ~BufferDirectory()
    {
        std::error_code ignored;
        std::filesystem::remove_all(path, ignored);
    }

    const std::filesystem::path path;
};

struct Segment
{
    Segment(std::shared_ptr<const BufferDirectory> directory, LONGLONG time)
        : directory(std::move(directory)), path(this->directory->path / (std::to_wstring(time) + L".mp4")), start(time)
    {}

    ~Segment()
    {
        std::error_code ignored;
        std::filesystem::remove(path, ignored);
    }

    const std::shared_ptr<const BufferDirectory> directory;
    const std::filesystem::path path;
    const LONGLONG start;
};

using Segments = std::deque<std::shared_ptr<const Segment>>;

class ReplayBuffer
{
public:
    explicit ReplayBuffer(const Settings& settings)
        : m_directory(std::make_shared<BufferDirectory>(settings.directory)), m_fps(settings.fps),
          m_limit(settings.minutes * 60 * second), m_quality(settings.quality), m_useHardware(settings.automaticEncoder)
    {}

    void clear()
    {
        m_writer = nullptr;
        m_current.reset();
        m_segments.clear();
    }

    void append(IMFSample* sample, SizeInt32 size, LONGLONG time)
    {
        if (m_writer && time - m_current->start >= segmentDuration)
            finish();
        if (!m_writer)
            start(size, time);

        const auto duration = second / m_fps;
        check_hresult(sample->SetSampleTime(time - m_current->start));
        check_hresult(sample->SetSampleDuration(duration));
        check_hresult(m_writer->WriteSample(m_stream, sample));
        while (!m_segments.empty() && m_segments.front()->start < time + duration - m_limit)
            m_segments.pop_front();
    }

    Segments snapshot()
    {
        finish();
        return m_segments;
    }

private:
    void start(SizeInt32 size, LONGLONG time)
    {
        m_current = std::make_shared<Segment>(m_directory, time);
        const auto output = videoType(MFVideoFormat_H264, size, m_fps);
        const auto factor = qualityFactors[m_quality];
        const auto bitrate = std::clamp<int64_t>(
            int64_t(size.Width) * size.Height * factor * m_fps / 100,
            75'000 * factor, 3'200'000 * factor);
        check_hresult(output->SetUINT32(MF_MT_AVG_BITRATE, static_cast<UINT32>(bitrate)));
        const auto input = videoType(MFVideoFormat_RGB32, size, m_fps);
        check_hresult(input->SetUINT32(MF_MT_DEFAULT_STRIDE, size.Width * 4));
        if (m_useHardware) {
            try {
                m_writer = openWriter(m_current->path, output.get(), input.get(), true, m_stream);
                return;
            } catch (const hresult_error&) {
                std::filesystem::remove(m_current->path);
                m_useHardware = false;
            }
        }
        m_writer = openWriter(m_current->path, output.get(), input.get(), false, m_stream);
    }

    void finish()
    {
        if (!m_writer)
            return;
        auto writer = std::exchange(m_writer, nullptr);
        check_hresult(writer->Finalize());
        m_segments.push_back(std::move(m_current));
    }

    std::shared_ptr<const BufferDirectory> m_directory;
    int m_fps;
    LONGLONG m_limit;
    int m_quality;
    bool m_useHardware;
    DWORD m_stream{};
    std::shared_ptr<const Segment> m_current;
    Segments m_segments;
    com_ptr<IMFSinkWriter> m_writer;
};

struct ExportJob
{
    Segments segments;
    int fps{};
    int format{};
    unsigned revision{};
};

void exportVideo(const ExportJob& job, const std::filesystem::path& path)
{
    // A single segment is already a playable MP4.
    if (job.segments.size() == 1) {
        std::filesystem::copy_file(job.segments.front()->path, path);
        return;
    }

    com_ptr<IMFSinkWriter> output;
    DWORD stream{};
    LONGLONG offset = 0;
    constexpr DWORD video = MF_SOURCE_READER_FIRST_VIDEO_STREAM;
    for (const auto& segment : job.segments) {
        com_ptr<IMFSourceReader> source;
        check_hresult(MFCreateSourceReaderFromURL(segment->path.c_str(), nullptr, source.put()));
        if (!output) {
            com_ptr<IMFMediaType> type;
            check_hresult(source->GetCurrentMediaType(video, type.put()));
            output = openWriter(path, type.get(), type.get(), false, stream);
        }
        LONGLONG end = offset;
        for (;;) {
            DWORD flags{};
            LONGLONG time{};
            com_ptr<IMFSample> sample;
            check_hresult(source->ReadSample(video, 0, nullptr, &flags, &time, sample.put()));
            if (sample) {
                LONGLONG duration = second / job.fps;
                sample->GetSampleDuration(&duration);
                check_hresult(sample->SetSampleTime(offset + time));
                check_hresult(output->WriteSample(stream, sample.get()));
                end = std::max(end, offset + time + duration);
            }
            if (flags & MF_SOURCE_READERF_ENDOFSTREAM)
                break;
        }
        offset = end;
    }
    check_hresult(output->Finalize());
}

std::string saveClip(const ExportJob& job)
{
    const auto& directory = job.segments.front()->directory->path;
    const auto name = L"Clip-" + uniqueId();
    const auto path = directory.parent_path() / (name + clipExtension(job.format));
    const auto input = directory / (name + L".mp4");
    const auto ffmpeg = job.format != 0 ? findFfmpeg() : std::wstring{};
    if (job.format != 0 && ffmpeg.empty())
        throw std::runtime_error("MKV and AVI require ffmpeg.exe next to the client.");

    try {
        if (job.format == 0) {
            exportVideo(job, path);
        } else {
            exportVideo(job, input);
            remuxClip(ffmpeg, input, path);
        }
    } catch (...) {
        std::error_code ignored;
        std::filesystem::remove(input, ignored);
        std::filesystem::remove(path, ignored);
        throw;
    }
    std::error_code ignored;
    std::filesystem::remove(input, ignored);
    return path.filename().string();
}

struct Apartment
{
    Apartment() { init_apartment(); }
    ~Apartment() { uninit_apartment(); }
};

struct MediaFoundation
{
    MediaFoundation() { check_hresult(MFStartup(MF_VERSION, MFSTARTUP_LITE)); }
    ~MediaFoundation() { MFShutdown(); }
};

struct Worker
{
    std::mutex mutex;
    std::condition_variable wake;
    std::condition_variable exportWake;
    std::thread captureThread;
    std::thread exportThread;
    Settings settings;
    unsigned revision{};
    std::optional<int> saveRequested;
    std::optional<ExportJob> exportJob;
    bool exporting{};
    bool stopping{};
    bool recording{};
    std::string status{"Off"};

    ~Worker() { stop(); }

    void stop()
    {
        {
            std::lock_guard guard(mutex);
            stopping = true;
            recording = false;
            saveRequested.reset();
        }
        wake.notify_one();
        exportWake.notify_one();
        if (captureThread.joinable())
            captureThread.join();
        if (exportThread.joinable())
            exportThread.join();
    }

    void runExports()
    {
        for (;;) {
            ExportJob job;
            {
                std::unique_lock guard(mutex);
                exportWake.wait(guard, [&] { return stopping || exportJob; });
                if (!exportJob)
                    return;
                job = std::move(*exportJob);
                exportJob.reset();
            }

            std::string result;
            try {
                const Apartment apartment;
                const MediaFoundation mediaFoundation;
                result = "Saved " + saveClip(job);
            } catch (const hresult_error& e) {
                result = "Could not save clip: " + to_string(e.message());
            } catch (const std::exception& e) {
                result = std::string("Could not save clip: ") + e.what();
            }
            job.segments.clear();

            std::lock_guard guard(mutex);
            exporting = false;
            if (!stopping && revision == job.revision && recording)
                status = std::move(result);
        }
    }

    void record(const Settings& config, unsigned activeRevision)
    {
        Capture capture;
        capture.start(config.window);
        ReplayBuffer buffer(config);
        {
            std::lock_guard guard(mutex);
            if (stopping || revision != activeRevision)
                return;
            status = "Buffering video...";
        }
        const auto period = second / config.fps;
        LONGLONG nextFrame = 0;
        bool hasFrame = false;
        for (;;) {
            std::optional<int> save;
            {
                std::unique_lock guard(mutex);
                wake.wait_for(guard, 4ms, [&] { return stopping || revision != activeRevision || saveRequested; });
                if (stopping || revision != activeRevision)
                    return;
                save = saveRequested;
            }

            if (save) {
                auto segments = buffer.snapshot();
                std::lock_guard guard(mutex);
                if (stopping || revision != activeRevision)
                    return;
                if (!exportThread.joinable()) {
                    try {
                        exportThread = std::thread([this] { runExports(); });
                    } catch (const std::system_error&) {
                        saveRequested.reset();
                        status = "Could not start clip export";
                    }
                }
                if (saveRequested) {
                    exportJob.emplace(ExportJob{std::move(segments), config.fps, *save, activeRevision});
                    exporting = true;
                    saveRequested.reset();
                    exportWake.notify_one();
                }
            }

            capture.updateBorder();
            auto frame = capture.pool.TryGetNextFrame();
            if (!frame)
                continue;
            const auto size = frame.ContentSize();
            if (size.Width < 2 || size.Height < 2)
                continue;
            if (size.Width != capture.size.Width || size.Height != capture.size.Height) {
                frame.Close();
                capture.resize(size);
                buffer.clear();
                hasFrame = false;
                nextFrame = 0;
                {
                    std::lock_guard guard(mutex);
                    if (revision == activeRevision) {
                        recording = false;
                        saveRequested.reset();
                        status = "Window resized. Buffering video...";
                    }
                }
                continue;
            }
            const auto time = frame.SystemRelativeTime().count();
            if (time + 10'000 < nextFrame)
                continue;
            nextFrame = std::max(nextFrame + period, time + period - 10'000);
            const auto outputSize = capture.videoSize(config.resolution);
            buffer.append(capture.copyFrame(frame, outputSize).get(), outputSize, time);
            if (!hasFrame) {
                hasFrame = true;
                std::lock_guard guard(mutex);
                if (!stopping && revision == activeRevision) {
                    recording = true;
                    status = "Recording";
                }
            }
        }
    }

    void run()
    {
        unsigned activeRevision = 0;
        while (true) {
            Settings config;
            {
                std::unique_lock guard(mutex);
                wake.wait(guard, [&] { return stopping || revision != activeRevision; });
                if (stopping)
                    break;
                activeRevision = revision;
                config = settings;
                if (!config.window) {
                    status = "Off";
                    continue;
                }
            }

            std::string failure;
            try {
                const Apartment apartment;
                const MediaFoundation mediaFoundation;
                record(config, activeRevision);
            } catch (const hresult_error& e) {
                failure = "Recording failed: " + to_string(e.message());
            } catch (const std::exception& e) {
                failure = std::string("Recording failed: ") + e.what();
            }
            std::lock_guard guard(mutex);
            if (!stopping && revision == activeRevision && !failure.empty()) {
                recording = false;
                saveRequested.reset();
                status = std::move(failure);
            }
        }
    }
};

Worker worker;
}

ClipRecorder g_clipRecorder;

void ClipRecorder::configure(void* window, std::string writeDir, int framesPerSecond, int bufferMinutes,
                             int resolution, int quality, bool automaticEncoder)
{
    std::lock_guard guard(worker.mutex);
    Settings settings;
    if (window) {
        if (writeDir.empty()) {
            worker.status = "The game user folder is unavailable";
            return;
        }
        settings.window = static_cast<HWND>(window);
        settings.directory = std::filesystem::u8path(writeDir) / "recordings";
        if (std::ranges::find(recordingFrameRates, framesPerSecond) != std::end(recordingFrameRates))
            settings.fps = framesPerSecond;
        settings.minutes = bufferMinutes == 10 ? 10 : 3;
        settings.resolution = resolution == 720 || resolution == 1080 ? resolution : 0;
        settings.quality = quality >= 0 && quality < static_cast<int>(std::size(qualityFactors)) ? quality : 1;
        settings.automaticEncoder = automaticEncoder;
    }
    if (worker.settings == settings || worker.stopping)
        return;
    if (window && !worker.captureThread.joinable()) {
        try {
            worker.captureThread = std::thread([] { worker.run(); });
        } catch (const std::system_error&) {
            worker.status = "Could not start clip recording";
            return;
        }
    }
    worker.settings = std::move(settings);
    worker.saveRequested.reset();
    worker.recording = false;
    ++worker.revision;
    worker.status = window ? "Starting recorder..." : "Off";
    worker.wake.notify_one();
}

bool ClipRecorder::save(int format)
{
    std::lock_guard guard(worker.mutex);
    if (!worker.recording || worker.saveRequested || worker.exporting)
        return false;
    worker.saveRequested = std::clamp(format, 0, 2);
    worker.status = "Saving clip...";
    worker.wake.notify_one();
    return true;
}

std::string ClipRecorder::status()
{
    std::lock_guard guard(worker.mutex);
    return worker.status;
}

bool ClipRecorder::isRecording()
{
    std::lock_guard guard(worker.mutex);
    return worker.recording;
}

void ClipRecorder::shutdown()
{
    worker.stop();
}

#endif
