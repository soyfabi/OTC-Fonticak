/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "resourcemanager.h"

#include <algorithm>
#include <cstring>
#include <limits>
#include <physfs.h>
#include <unordered_set>

#include "filestream.h"
#include "graphicalapplication.h"
#include "framework/graphics/drawpoolmanager.h"
#include "framework/net/protocolhttp.h"
#include "framework/platform/platform.h"
#include "framework/util/crypt.h"
#include "logger.h"

#include "framework/core/minizip/ioapi.h"
#include "framework/core/minizip/ioapi_mem.h"
#include "framework/core/minizip/unzip.h"
#include "framework/core/minizip/zip.h"

ResourceManager g_resources;

namespace
{
constexpr size_t MAX_ARCHIVE_ENTRIES = 512;
constexpr size_t MAX_ARCHIVE_FILE_SIZE = 16 * 1024 * 1024;
constexpr size_t MAX_ARCHIVE_TOTAL_SIZE = 32 * 1024 * 1024;
constexpr size_t MAX_ARCHIVE_NAME_SIZE = 1023;

bool hasZipMagic(const std::string& data)
{
    if (data.size() < 4 || data[0] != 'P' || data[1] != 'K')
        return false;

    const auto third = static_cast<unsigned char>(data[2]);
    const auto fourth = static_cast<unsigned char>(data[3]);
    return (third == 3 && fourth == 4) || (third == 5 && fourth == 6);
}

bool normalizeArchiveName(const std::string& input, std::string& output)
{
    if (input.empty() || input.size() > MAX_ARCHIVE_NAME_SIZE ||
        input.front() == '/' || input.front() == '\\' || input.find(':') != std::string::npos)
        return false;

    output = input;
    std::replace(output.begin(), output.end(), '\\', '/');
    if (output.empty() || output.size() > MAX_ARCHIVE_NAME_SIZE)
        return false;

    size_t componentStart = 0;
    while (componentStart <= output.size()) {
        const size_t separator = output.find('/', componentStart);
        const size_t componentEnd = separator == std::string::npos ? output.size() : separator;
        const size_t componentSize = componentEnd - componentStart;
        if (componentSize == 0 ||
            (componentSize == 1 && output[componentStart] == '.') ||
            (componentSize == 2 && output[componentStart] == '.' && output[componentStart + 1] == '.'))
            return false;

        if (separator == std::string::npos)
            break;
        componentStart = separator + 1;
    }

    return true;
}
}

void ResourceManager::init(const char* argv0)
{
    PHYSFS_init(argv0);
    PHYSFS_permitSymbolicLinks(1);

#if defined(WIN32)
    char fileName[255];
    GetModuleFileNameA(nullptr, fileName, sizeof(fileName));
    m_binaryPath = std::filesystem::absolute(fileName);
#elif defined(ANDROID)
    // nothing
#else
    m_binaryPath = std::filesystem::absolute(argv0);
#endif
}

void ResourceManager::terminate()
{
    PHYSFS_deinit();
}

bool ResourceManager::discoverWorkDir(const std::string& existentFile)
{
    // search for modules directory
    std::string possiblePaths[] = { g_platform.getCurrentDir(),
                                    g_resources.getBaseDir(),
                                    g_resources.getBaseDir() + "/game_data/",
                                    g_resources.getBaseDir() + "../",
                                    g_resources.getBaseDir() + "../share/" + g_app.getCompactName() + "/" };

    bool found = false;
    for (const auto& dir : possiblePaths) {
        if (!PHYSFS_mount(dir.c_str(), nullptr, 0))
            continue;

        if (PHYSFS_exists(existentFile.c_str())) {
            g_logger.debug("Found work dir at '{}'", dir);
            m_workDir = dir;
            found = true;
            break;
        }
        PHYSFS_unmount(dir.c_str());
    }

    return found;
}

bool ResourceManager::setupUserWriteDir(const std::string& appWriteDirName)
{
    const std::string userDir = getUserDir();
    std::string dirName;
#ifndef WIN32
    dirName = fmt::format(".{}", appWriteDirName);
#else
    dirName = appWriteDirName;
#endif
    const std::string writeDir = userDir + dirName;

    if (!PHYSFS_setWriteDir(writeDir.c_str())) {
        if (!PHYSFS_setWriteDir(userDir.c_str()) || !PHYSFS_mkdir(dirName.c_str())) {
            g_logger.error(
                "Unable to create write directory '{}': {}",
                writeDir,
                PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())
            );
            return false;
        }
    }
    return setWriteDir(writeDir);
}

bool ResourceManager::setWriteDir(const std::string& writeDir, bool)
{
    if (!PHYSFS_setWriteDir(writeDir.c_str())) {
        g_logger.error(
            "Unable to set write directory '{}': {}",
            writeDir,
            PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())
        );
        return false;
    }

    if (!m_writeDir.empty())
        removeSearchPath(m_writeDir);

    m_writeDir = writeDir;

    if (!addSearchPath(writeDir))
        g_logger.error("Unable to add write '{}' directory to search path", writeDir);

    return true;
}

bool ResourceManager::addSearchPath(const std::string& path, const bool pushFront)
{
    std::string savePath = path;
    if (!PHYSFS_mount(path.c_str(), nullptr, pushFront ? 0 : 1)) {
        bool found = false;
        for (const auto& searchPath : m_searchPaths) {
            std::string newPath = searchPath + path;
            if (PHYSFS_mount(newPath.c_str(), nullptr, pushFront ? 0 : 1)) {
                savePath = newPath;
                found = true;
                break;
            }
        }

        if (!found) {
            /*g_logger.error(
                "Could not add '{}' to directory search path. Reason {}",
                path,
                PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())
            );
            */

            return false;
        }
    }
    if (pushFront)
        m_searchPaths.push_front(savePath);
    else
        m_searchPaths.push_back(savePath);
    return true;
}

bool ResourceManager::removeSearchPath(const std::string& path)
{
    if (!PHYSFS_unmount(path.c_str()))
        return false;
    const auto it = std::ranges::find(m_searchPaths, path);
    assert(it != m_searchPaths.end());
    m_searchPaths.erase(it);
    return true;
}

void ResourceManager::searchAndAddPackages(const std::string& packagesDir, const std::string& packageExt)
{
    auto files = listDirectoryFiles(packagesDir);
    for (auto& file : std::ranges::reverse_view(files)) {
        if (!file.ends_with(packageExt))
            continue;
        std::string package = getRealDir(packagesDir) + "/" + file;
        if (!addSearchPath(package, true))
            g_logger.error(
                "Unable to read package '{}': {}",
                package,
                PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())
            );
    }
}

bool ResourceManager::fileExists(const std::string& fileName)
{
    if (fileName.find("/downloads") != std::string::npos)
        return g_http.getFile(fileName.substr(10)) != nullptr;

    return (PHYSFS_exists(resolvePath(fileName).c_str()) && !directoryExists(fileName));
}

bool ResourceManager::directoryExists(const std::string& directoryName)
{
    if (directoryName == "/downloads")
        return true;

    PHYSFS_Stat stat = {};
    if (!PHYSFS_stat(resolvePath(directoryName).c_str(), &stat)) {
        return false;
    }

    return stat.filetype == PHYSFS_FILETYPE_DIRECTORY;
}

void ResourceManager::readFileStream(const std::string& fileName, std::iostream& out)
{
    const std::string buffer = readFileContents(fileName);
    if (buffer.length() == 0) {
        out.clear(std::ios::eofbit);
        return;
    }
    out.clear(std::ios::goodbit);
    out.write(&buffer[0], buffer.length());
    out.seekg(0, std::ios::beg);
}

std::string ResourceManager::readFileContents(const std::string& fileName)
{
    const std::string fullPath = resolvePath(fileName);

    if (fullPath.find(AY_OBFUSCATE("/downloads")) != std::string::npos) {
        const auto dfile = g_http.getFile(fullPath.substr(10));
        if (dfile)
            return std::string(dfile->response.begin(), dfile->response.end());
    }

    PHYSFS_File* file = PHYSFS_openRead(fullPath.c_str());
    if (!file)
        throw Exception("unable to open file '{}': {}", fullPath, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode()));

    const int fileSize = PHYSFS_fileLength(file);
    std::string buffer(fileSize, 0);
    PHYSFS_readBytes(file, &buffer[0], fileSize);
    PHYSFS_close(file);

#if ENABLE_ENCRYPTION == 1
    const std::string encHeader(ENCRYPTION_HEADER);
    if (buffer.size() >= encHeader.size() &&
        buffer.compare(0, encHeader.size(), encHeader) == 0) {
        buffer = buffer.substr(encHeader.size());
        buffer = decrypt(buffer);
    }
#endif

    return buffer;
}

bool ResourceManager::writeFileBuffer(const std::string& fileName, const uint8_t* data, const uint32_t size, const bool createDirectory)
{
    if (createDirectory) {
        const auto& path = std::filesystem::path(fileName);
        const auto& dirPath = path.parent_path().string();

        if (!PHYSFS_isDirectory(dirPath.c_str())) {
            if (!PHYSFS_mkdir(dirPath.c_str())) {
                g_logger.error(
                    "Unable to create write directory '{}': {}",
                    dirPath,
                    PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())
                );
                return false;
            }
        }
    }

    PHYSFS_file* file = PHYSFS_openWrite(fileName.c_str());
    if (!file) {
        g_logger.error(PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode()));
        return false;
    }

    PHYSFS_writeBytes(file, data, size);
    PHYSFS_close(file);
    return true;
}

bool ResourceManager::writeFileStream(const std::string& fileName, std::iostream& in)
{
    const std::streampos oldPos = in.tellg();
    in.seekg(0, std::ios::end);
    const std::streampos size = in.tellg();
    in.seekg(0, std::ios::beg);
    std::vector<char> buffer(size);
    in.read(&buffer[0], size);
    const bool ret = writeFileBuffer(fileName, (const uint8_t*)&buffer[0], size);
    in.seekg(oldPos, std::ios::beg);
    return ret;
}

bool ResourceManager::writeFileContents(const std::string& fileName, const std::string& data)
{
    return writeFileBuffer(fileName, (const uint8_t*)data.c_str(), data.size());
}

bool ResourceManager::writeFileContentsToWorkDir(const std::string& fileName, const std::string& data)
{
    const auto oldWriteDir = getWriteDir();
    if (!setWriteDir(getWorkDir()))
        return false;

    const bool ok = writeFileBuffer(fileName, reinterpret_cast<const uint8_t*>(data.c_str()), static_cast<uint32_t>(data.size()), true);
    setWriteDir(oldWriteDir);
    addSearchPath(getWorkDir(), true);
    return ok;
}

FileStreamPtr ResourceManager::openFile(const std::string& fileName)
{
    const std::string fullPath = resolvePath(fileName);

    PHYSFS_File* file = PHYSFS_openRead(fullPath.c_str());
    if (!file)
        throw Exception("unable to open file '{}': {}", fullPath, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode()));
    return { std::make_shared<FileStream>(fullPath, file, false) };
}

FileStreamPtr ResourceManager::appendFile(const std::string& fileName) const
{
    PHYSFS_File* file = PHYSFS_openAppend(fileName.c_str());
    if (!file)
        throw Exception("failed to append file '{}': {}", fileName, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode()));
    return { std::make_shared<FileStream>(fileName, file, true) };
}

FileStreamPtr ResourceManager::createFile(const std::string& fileName) const
{
    PHYSFS_File* file = PHYSFS_openWrite(fileName.c_str());
    if (!file)
        throw Exception("failed to create file '{}': {}", fileName, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode()));
    return { std::make_shared<FileStream>(fileName, file, true) };
}

bool ResourceManager::deleteFile(const std::string& fileName)
{
    return PHYSFS_delete(resolvePath(fileName).c_str()) != 0;
}

bool ResourceManager::makeDir(const std::string& directory)
{
    return PHYSFS_mkdir(directory.c_str());
}

std::list<std::string> ResourceManager::listDirectoryFiles(const std::string& directoryPath, const bool fullPath /* = false */, const bool raw /*= false*/, const bool recursive)
{
    std::list<std::string> files;
    const auto path = raw ? directoryPath : resolvePath(directoryPath);
    const auto rc = PHYSFS_enumerateFiles(path.c_str());

    if (!rc)
        return files;

    for (int i = 0; rc[i] != nullptr; i++) {
        std::string fileOrDir = rc[i];
        if (fullPath) {
            if (path != "/")
                fileOrDir = path + "/" + fileOrDir;
            else
                fileOrDir = path + fileOrDir;
        }

        if (recursive && directoryExists("/" + fileOrDir)) {
            const auto& moreFiles = listDirectoryFiles(fileOrDir, fullPath, raw, recursive);
            files.insert(files.end(), moreFiles.begin(), moreFiles.end());
        } else {
            files.push_back(fileOrDir);
        }
    }

    PHYSFS_freeList(rc);
    files.sort();
    return files;
}

std::vector<std::string> ResourceManager::getDirectoryFiles(const std::string& path, const bool filenameOnly, const bool recursive)
{
    if (!std::filesystem::exists(path))
        return {};

    const std::filesystem::path p(path);
    return discoverPath(p, filenameOnly, recursive);
}

std::vector<std::string> ResourceManager::discoverPath(const std::filesystem::path& path, const bool filenameOnly, const bool recursive)
{
    std::vector<std::string> files;

    /* Before doing anything, we have to add this directory to search path,
     * this is needed so it works correctly when one wants to open a file.  */
    addSearchPath(path.generic_string(), true);
    for (std::filesystem::directory_iterator it(path), end; it != end; ++it) {
        if (std::filesystem::is_directory(it->path().generic_string()) && recursive) {
            std::vector<std::string> subfiles = discoverPath(it->path(), filenameOnly, recursive);
            files.insert(files.end(), subfiles.begin(), subfiles.end());
        } else {
            if (filenameOnly)
                files.push_back(it->path().filename().string());
            else
                files.push_back(it->path().generic_string() + "/" + it->path().filename().string());
        }
    }

    return files;
}

std::string ResourceManager::resolvePath(const std::string& path)
{
    std::string fullPath;
    if (path.starts_with("/"))
        fullPath = path;
    else if (g_drawPool.isPreDrawing())
        fullPath = "/" + path;
    else {
        if (const std::string scriptPath = "/" + g_lua.getCurrentSourcePath(); !scriptPath.empty())
            fullPath += scriptPath + "/";
        fullPath += path;
    }

    if (!(fullPath.starts_with("/")))
        g_logger.traceWarning(fmt::format("the following file path is not fully resolved: {}", path));

    stdext::replace_all(fullPath, "//", "/");
    return fullPath;
}

std::string ResourceManager::getRealDir(const std::string& path)
{
    std::string dir;
    if (const char* cdir = PHYSFS_getRealDir(resolvePath(path).c_str()))
        dir = cdir;
    return dir;
}

std::string ResourceManager::getRealPath(const std::string& path)
{
    return getRealDir(path) + "/" + path;
}

std::string ResourceManager::getBaseDir()
{
#ifdef ANDROID
    return g_androidManager.getAppBaseDir();
#else
    return PHYSFS_getBaseDir();
#endif
}

std::string ResourceManager::getUserDir()
{
#ifdef ANDROID
    return getBaseDir() + "/";
#elif defined(__EMSCRIPTEN__)
    return "/user/";
#else
    static const char* orgName = g_app.getOrganizationName().data();
    static const char* appName = g_app.getCompactName().data();

    return PHYSFS_getPrefDir(orgName, appName);
#endif
}

std::string ResourceManager::guessFilePath(const std::string& filename, const std::string& type)
{
    if (isFileType(filename, type))
        return filename;
    return filename + "." + type;
}

bool ResourceManager::isFileType(const std::string& filename, const std::string& type)
{
    if (filename.ends_with(std::string(".") + type))
        return true;
    return false;
}

std::string ResourceManager::getFileName(const std::string& filePath)
{
    return std::filesystem::path(filePath).filename().string();
}

ticks_t ResourceManager::getFileTime(const std::string& filename)
{
    return g_platform.getFileModificationTime(getRealPath(filename));
}

std::string ResourceManager::encrypt(const std::string& data, const std::string& password)
{
    const int len = data.length(),
        plen = password.length();

    std::ostringstream ss;
    int j = 0;
    for (int i = -1; ++i < len;) {
        int ct = data[i];
        if (i % 2) {
            ct = ct - password[j] + i;
        } else {
            ct = ct + password[j] - i;
        }
        ss << static_cast<char>(ct);
        ++j;

        if (j >= plen)
            j = 0;
    }

    return ss.str();
}
std::string ResourceManager::decrypt(const std::string& data)
{
    const auto& password = std::string(ENCRYPTION_PASSWORD);

    const int len = data.length(),
        plen = password.length();

    std::ostringstream ss;
    int j = 0;
    for (int i = -1; ++i < len;) {
        int ct = data[i];
        if (i % 2) {
            ct = ct + password[j] - i;
        } else {
            ct = ct - password[j] + i;
        }
        ss << static_cast<char>(ct);
        ++j;

        if (j >= plen)
            j = 0;
    }

    return ss.str();
}

uint8_t* ResourceManager::decrypt(uint8_t* data, const int32_t size)
{
    const auto& password = std::string(ENCRYPTION_PASSWORD);
    const int plen = password.length();

    int j = 0;
    for (int i = -1; ++i < size;) {
        const int ct = data[i];
        if (i % 2) {
            data[i] = ct + password[j] - i;
        } else {
            data[i] = ct - password[j] + i;
        }
        ++j;

        if (j >= plen)
            j = 0;
    }

    return data;
}

void ResourceManager::runEncryption(const std::string& password)
{
    std::vector<std::string> excludedExtensions = { ".rar",".ogg",".xml",".dll",".exe", ".log",".otb" };
    for (const auto& entry : std::filesystem::recursive_directory_iterator("./")) {
        if (std::string ext = entry.path().extension().string();
            std::ranges::find(excludedExtensions, ext) != excludedExtensions.end())
            continue;

        std::ifstream ifs(entry.path().string(), std::ios_base::binary);
        std::string data((std::istreambuf_iterator(ifs)), std::istreambuf_iterator<char>());
        ifs.close();
        data = encrypt(data, password);
        std::string finalData = std::string(ENCRYPTION_HEADER) + data;
        save_string_into_file(finalData, entry.path().string());
    }
}

void ResourceManager::save_string_into_file(const std::string& contents, const std::string& name)
{
    std::ofstream datFile;
    datFile.open(name, std::ofstream::binary | std::ofstream::trunc | std::ofstream::out);
    datFile.write(contents.c_str(), contents.size());
    datFile.close();
}

std::string ResourceManager::fileChecksum(const std::string& path) {
    static stdext::map<std::string, std::string> cache;

    const auto it = cache.find(path);
    if (it != cache.end())
        return it->second;

    PHYSFS_File* file = PHYSFS_openRead(path.c_str());
    if (!file)
        return "";

    const int fileSize = PHYSFS_fileLength(file);
    std::string buffer(fileSize, 0);
    PHYSFS_readBytes(file, &buffer[0], fileSize);
    PHYSFS_close(file);

    auto checksum = g_crypt.crc32(buffer, false);
    cache[path] = checksum;

    return checksum;
}

std::unordered_map<std::string, std::string> ResourceManager::filesChecksums()
{
    std::unordered_map<std::string, std::string> ret;
    auto files = listDirectoryFiles("/", true, false, true);
    for (auto& filePath : std::ranges::reverse_view(files)) {
        PHYSFS_File* file = PHYSFS_openRead(filePath.c_str());
        if (!file)
            continue;

        const int fileSize = PHYSFS_fileLength(file);
        std::string buffer(fileSize, 0);
        PHYSFS_readBytes(file, &buffer[0], fileSize);
        PHYSFS_close(file);

        const auto checksum = g_crypt.crc32(buffer, false);
        ret[filePath] = checksum;
    }

    return ret;
}

std::string ResourceManager::selfChecksum() {
#ifdef ANDROID
    return "";
#else
    static std::string checksum;
    if (!checksum.empty())
        return checksum;

    std::ifstream file(m_binaryPath.string(), std::ios::binary);
    if (!file.is_open())
        return "";

    std::string buffer(std::istreambuf_iterator<char>(file), {});
    file.close();

    checksum = g_crypt.crc32(buffer, false);
    return checksum;
#endif
}

void ResourceManager::updateFiles(const std::set<std::string>& files) {
    g_logger.info("Updating client, {} files", files.size());

    const auto& oldWriteDir = getWriteDir();
    setWriteDir(getWorkDir());
    for (auto fileName : files) {
        if (fileName.empty())
            continue;

        if (fileName.size() > 1 && fileName[0] == '/')
            fileName = fileName.substr(1);

        auto dFile = g_http.getFile(fileName);

        if (dFile) {
            if (!writeFileBuffer(fileName, (const uint8_t*)dFile->response.data(), dFile->response.size(), true)) {
                g_logger.error("Cannot write file: {}", fileName);
            } else {
                //g_logger.info("Updated file: {}", fileName);
            }
        } else {
            g_logger.error("Cannot find file: {} in downloads", fileName);
        }
    }
    setWriteDir(oldWriteDir);
    addSearchPath(getWorkDir(), true);
}

void ResourceManager::updateExecutable(std::string fileName)
{
#if defined(ANDROID) || defined(FREE_VERSION)
    g_logger.fatal("Executable cannot be updated on android or in free version");
#else
    if (fileName.size() <= 2) {
        g_logger.fatal("Invalid executable name");
    }

    if (fileName[0] == '/')
        fileName = fileName.substr(1);

    const auto dFile = g_http.getFile(fileName);
    if (!dFile)
        g_logger.fatal("Cannot find executable: {} in downloads", fileName);

    const auto& oldWriteDir = getWriteDir();
    setWriteDir(getWorkDir());
    const std::filesystem::path path(m_binaryPath);
    const auto newBinary = path.stem().string() + "-" + std::to_string(time(nullptr)) + path.extension().string();
    g_logger.info("Updating binary file: {}", newBinary);
    PHYSFS_file* file = PHYSFS_openWrite(newBinary.c_str());
    if (!file) {
        return g_logger.fatal(
            "can't open {} for writing: {}",
            newBinary,
            PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())
        );
    }

    PHYSFS_writeBytes(file, dFile->response.data(), dFile->response.size());
    PHYSFS_close(file);
    setWriteDir(oldWriteDir);

    std::filesystem::path newBinaryPath(std::filesystem::u8path(PHYSFS_getWriteDir()));
#endif
}

bool ResourceManager::launchCorrect(const std::vector<std::string>& args) { // curently works only on windows
#if (defined(ANDROID) || defined(FREE_VERSION))
    return false;
#else
    auto fileName2 = m_binaryPath.stem().string();
    fileName2 = stdext::split(fileName2, "-")[0];
    stdext::tolower(fileName2);

    const std::filesystem::path path(m_binaryPath.parent_path());
    std::error_code ec;
    auto lastWrite = last_write_time(m_binaryPath, ec);
    std::filesystem::path binary = m_binaryPath;
    for (auto& entry : std::filesystem::directory_iterator(path)) {
        if (is_directory(entry.path()))
            continue;

        auto fileName1 = entry.path().stem().string();
        fileName1 = stdext::split(fileName1, "-")[0];
        stdext::tolower(fileName1);
        if (fileName1 != fileName2)
            continue;

        if (entry.path().extension() == m_binaryPath.extension()) {
            std::error_code _ec;
            auto writeTime = last_write_time(entry.path(), _ec);
            if (!_ec && writeTime > lastWrite) {
                lastWrite = writeTime;
                binary = entry.path();
            }
        }
    }

    for (auto& entry : std::filesystem::directory_iterator(path)) { // remove old
        if (is_directory(entry.path()))
            continue;

        auto fileName1 = entry.path().stem().string();
        fileName1 = stdext::split(fileName1, "-")[0];
        stdext::tolower(fileName1);
        if (fileName1 != fileName2)
            continue;

        if (entry.path().extension() == m_binaryPath.extension()) {
            if (binary == entry.path())
                continue;
            std::error_code _ec;
            std::filesystem::remove(entry.path(), _ec);
        }
    }

    if (binary == m_binaryPath)
        return false;

    g_platform.spawnProcess(binary.string(), args);
    return true;
#endif
}

std::string ResourceManager::createArchive(const std::unordered_map<std::string, std::string>& files)
{
    if (files.empty())
        return {};

    if (files.size() > MAX_ARCHIVE_ENTRIES) {
        g_logger.error("createArchive: too many entries (maximum {})", MAX_ARCHIVE_ENTRIES);
        return {};
    }

    struct ArchiveEntry {
        std::string name;
        const std::string* contents;
    };
    std::vector<ArchiveEntry> entries;
    entries.reserve(files.size());
    std::unordered_set<std::string> normalizedNames;
    size_t totalSize = 0;

    for (const auto& [name, contents] : files) {
        std::string normalizedName;
        if (!normalizeArchiveName(name, normalizedName)) {
            g_logger.error("createArchive: invalid entry name '{}'", name);
            return {};
        }
        if (!normalizedNames.emplace(normalizedName).second) {
            g_logger.error("createArchive: duplicate normalized entry name '{}'", normalizedName);
            return {};
        }
        if (contents.size() > MAX_ARCHIVE_FILE_SIZE) {
            g_logger.error("createArchive: entry '{}' exceeds the {} byte limit", normalizedName, MAX_ARCHIVE_FILE_SIZE);
            return {};
        }
        if (contents.size() > MAX_ARCHIVE_TOTAL_SIZE - totalSize) {
            g_logger.error("createArchive: uncompressed contents exceed the {} byte total limit", MAX_ARCHIVE_TOTAL_SIZE);
            return {};
        }
        totalSize += contents.size();
        entries.push_back({ std::move(normalizedName), &contents });
    }

    zlib_filefunc_def filefunc32 = {};
    ourmemory_t zipmem = {};
    zipmem.grow = 1;

    fill_memory_filefunc(&filefunc32, &zipmem);
    zipFile zipfile = zipOpen2(nullptr, APPEND_STATUS_CREATE, nullptr, &filefunc32);
    if (!zipfile) {
        g_logger.error("createArchive: unable to open in-memory zip");
        free(zipmem.base);
        return {};
    }

    for (const auto& entry : entries) {
        zip_fileinfo zi = {};
        if (zipOpenNewFileInZip(zipfile, entry.name.c_str(), &zi,
                                nullptr, 0, nullptr, 0, nullptr,
                                Z_DEFLATED, Z_DEFAULT_COMPRESSION) != ZIP_OK) {
            g_logger.error("createArchive: unable to add '{}'", entry.name);
            zipClose(zipfile, nullptr);
            free(zipmem.base);
            return {};
        }

        if (!entry.contents->empty()) {
            if (zipWriteInFileInZip(zipfile, entry.contents->data(), static_cast<uint32_t>(entry.contents->size())) != ZIP_OK) {
                g_logger.error("createArchive: unable to write '{}'", entry.name);
                zipCloseFileInZip(zipfile);
                zipClose(zipfile, nullptr);
                free(zipmem.base);
                return {};
            }
        }

        if (zipCloseFileInZip(zipfile) != ZIP_OK) {
            g_logger.error("createArchive: unable to close entry '{}'", entry.name);
            zipClose(zipfile, nullptr);
            free(zipmem.base);
            return {};
        }
    }

    if (zipClose(zipfile, nullptr) != ZIP_OK) {
        g_logger.error("createArchive: unable to finalize zip");
        free(zipmem.base);
        return {};
    }

    std::string archive;
    if (zipmem.base && zipmem.limit > 0)
        archive.assign(zipmem.base, zipmem.limit);

    free(zipmem.base);
    return archive;
}

std::unordered_map<std::string, std::string> ResourceManager::decompressArchive(std::string dataOrPath)
{
    std::unordered_map<std::string, std::string> ret;
    if (dataOrPath.empty())
        return ret;

    std::string data = dataOrPath;
    const bool canBePath = dataOrPath.size() < 4096 && dataOrPath.find('\0') == std::string::npos;
    const bool looksLikePath = canBePath &&
        (dataOrPath.find('/') != std::string::npos || dataOrPath.find('\\') != std::string::npos);
    if (!hasZipMagic(dataOrPath) && canBePath && (looksLikePath || fileExists(dataOrPath))) {
        try {
            data = readFileContents(dataOrPath);
        } catch (const stdext::exception& e) {
            g_logger.error("decompressArchive: {}", e.what());
            return ret;
        }
    }

    if (!hasZipMagic(data)) {
        g_logger.error("decompressArchive: input does not have a valid ZIP signature");
        return ret;
    }
    if (data.size() > std::numeric_limits<uint32_t>::max()) {
        g_logger.error("decompressArchive: input exceeds the uint32 memory backend limit");
        return ret;
    }

    zlib_filefunc_def filefunc32 = {};
    ourmemory_t unzmem = {};
    unzmem.size = static_cast<uint32_t>(data.size());
    unzmem.base = static_cast<char*>(malloc(unzmem.size));
    if (!unzmem.base) {
        g_logger.error("decompressArchive: unable to allocate {} bytes for ZIP input", unzmem.size);
        return ret;
    }

    memcpy(unzmem.base, data.data(), unzmem.size);
    fill_memory_filefunc(&filefunc32, &unzmem);

    unzFile zipfile = unzOpen2(nullptr, &filefunc32);
    if (!zipfile) {
        free(unzmem.base);
        g_logger.error("decompressArchive: invalid zip archive");
        return ret;
    }

    unz_global_info globalInfo = {};
    if (unzGetGlobalInfo(zipfile, &globalInfo) != UNZ_OK) {
        unzClose(zipfile);
        free(unzmem.base);
        g_logger.error("decompressArchive: unable to read zip global info");
        return ret;
    }
    if (globalInfo.number_entry > MAX_ARCHIVE_ENTRIES) {
        g_logger.error("decompressArchive: too many entries (maximum {})", MAX_ARCHIVE_ENTRIES);
        unzClose(zipfile);
        free(unzmem.base);
        return ret;
    }

    constexpr int READ_SIZE = 8192;
    char readBuffer[READ_SIZE];
    size_t totalSize = 0;
    bool valid = true;

    for (uLong i = 0; i < globalInfo.number_entry; ++i) {
        unz_file_info fileInfo = {};
        if (unzGetCurrentFileInfo(zipfile, &fileInfo, nullptr, 0, nullptr, 0, nullptr, 0) != UNZ_OK) {
            g_logger.error("decompressArchive: unable to read file info");
            valid = false;
            break;
        }

        if (fileInfo.size_filename == 0 || fileInfo.size_filename > MAX_ARCHIVE_NAME_SIZE) {
            g_logger.error("decompressArchive: invalid entry name length {}", fileInfo.size_filename);
            valid = false;
            break;
        }

        char filename[MAX_ARCHIVE_NAME_SIZE + 1] = {};
        if (unzGetCurrentFileInfo(zipfile, &fileInfo, filename, sizeof(filename), nullptr, 0, nullptr, 0) != UNZ_OK) {
            g_logger.error("decompressArchive: unable to read entry name");
            valid = false;
            break;
        }

        std::string rawName(filename, fileInfo.size_filename);
        const bool isDirectory = !rawName.empty() && (rawName.back() == '/' || rawName.back() == '\\');
        if (isDirectory)
            rawName.pop_back();

        std::string entryName;
        if (!normalizeArchiveName(rawName, entryName)) {
            g_logger.error("decompressArchive: unsafe entry name");
            valid = false;
            break;
        }
        if (isDirectory) {
            if (fileInfo.uncompressed_size != 0) {
                g_logger.error("decompressArchive: directory '{}' contains data", entryName);
                valid = false;
                break;
            }
            if ((i + 1) < globalInfo.number_entry && unzGoToNextFile(zipfile) != UNZ_OK) {
                g_logger.error("decompressArchive: unable to go to next file");
                valid = false;
                break;
            }
            continue;
        }
        const std::string resultName = "/" + entryName;
        if (ret.contains(resultName)) {
            g_logger.error("decompressArchive: duplicate entry '{}'", entryName);
            valid = false;
            break;
        }
        if (fileInfo.uncompressed_size > MAX_ARCHIVE_FILE_SIZE ||
            fileInfo.uncompressed_size > MAX_ARCHIVE_TOTAL_SIZE - totalSize) {
            g_logger.error("decompressArchive: entry '{}' exceeds extraction limits", entryName);
            valid = false;
            break;
        }
        if (unzOpenCurrentFile(zipfile) != UNZ_OK) {
            g_logger.error("decompressArchive: unable to open '{}'", entryName);
            valid = false;
            break;
        }

        std::string contents;
        int readResult = UNZ_OK;
        while ((readResult = unzReadCurrentFile(zipfile, readBuffer, READ_SIZE)) > 0) {
            if (static_cast<size_t>(readResult) > MAX_ARCHIVE_FILE_SIZE - contents.size() ||
                static_cast<size_t>(readResult) > MAX_ARCHIVE_TOTAL_SIZE - totalSize - contents.size()) {
                g_logger.error("decompressArchive: entry '{}' exceeded extraction limits while reading", entryName);
                valid = false;
                break;
            }
            contents.append(readBuffer, static_cast<size_t>(readResult));
        }
        if (readResult < 0) {
            g_logger.error("decompressArchive: read error {} on '{}'", readResult, entryName);
            valid = false;
        }

        const int closeResult = unzCloseCurrentFile(zipfile);
        if (closeResult != UNZ_OK) {
            g_logger.error("decompressArchive: close/CRC error {} on '{}'", closeResult, entryName);
            valid = false;
        }
        if (!valid)
            break;
        if (contents.size() != fileInfo.uncompressed_size) {
            g_logger.error("decompressArchive: size mismatch on '{}'", entryName);
            valid = false;
            break;
        }
        totalSize += contents.size();
        ret.emplace(resultName, std::move(contents));

        if ((i + 1) < globalInfo.number_entry && unzGoToNextFile(zipfile) != UNZ_OK) {
            g_logger.error("decompressArchive: unable to go to next file");
            valid = false;
            break;
        }
    }

    if (unzClose(zipfile) != UNZ_OK) {
        g_logger.error("decompressArchive: unable to close zip archive");
        valid = false;
    }
    free(unzmem.base);
    return valid ? ret : std::unordered_map<std::string, std::string>{};
}