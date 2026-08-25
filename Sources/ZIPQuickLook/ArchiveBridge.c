#include "ArchiveBridge.h"

#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

typedef struct archive archive_t;
typedef struct archive_entry archive_entry_t;

extern archive_t *archive_read_new(void);
extern int archive_read_support_filter_all(archive_t *archive);
extern int archive_read_support_format_all(archive_t *archive);
extern int archive_read_open_filename(archive_t *archive, const char *filename, size_t blockSize);
extern int archive_read_next_header(archive_t *archive, archive_entry_t **entry);
extern ssize_t archive_read_data(archive_t *archive, void *buffer, size_t length);
extern int archive_read_data_skip(archive_t *archive);
extern int archive_read_free(archive_t *archive);
extern const char *archive_error_string(archive_t *archive);
extern const char *archive_entry_pathname_utf8(archive_entry_t *entry);
extern const char *archive_entry_pathname(archive_entry_t *entry);
extern int archive_entry_filetype(archive_entry_t *entry);
extern const char *archive_entry_hardlink(archive_entry_t *entry);

enum {
    ZIP_ARCHIVE_OK = 0,
    ZIP_ARCHIVE_EOF = 1,
    ZIP_ARCHIVE_IFREG = 0100000
};

static _Thread_local char ZIPLastError[512];

struct ZIPArchiveReader {
    archive_t *archive;
};

ZIPArchiveReader *ZIPArchiveReaderCreate(const char *path) {
    ZIPArchiveReader *reader = calloc(1, sizeof(*reader));
    if (reader == NULL) return NULL;

    reader->archive = archive_read_new();
    if (reader->archive == NULL) {
        free(reader);
        return NULL;
    }
    archive_read_support_filter_all(reader->archive);
    archive_read_support_format_all(reader->archive);
    if (archive_read_open_filename(reader->archive, path, 10240) < ZIP_ARCHIVE_OK) {
        archive_read_free(reader->archive);
        free(reader);
        return NULL;
    }
    return reader;
}

int ZIPArchiveReaderNext(ZIPArchiveReader *reader, const char **path, int *isDirectory) {
    archive_entry_t *entry = NULL;
    int status = archive_read_next_header(reader->archive, &entry);
    if (status == ZIP_ARCHIVE_EOF) return 0;
    if (status < ZIP_ARCHIVE_OK) return -1;

    const char *entryPath = archive_entry_pathname_utf8(entry);
    if (entryPath == NULL) entryPath = archive_entry_pathname(entry);
    *path = entryPath;
    *isDirectory = archive_entry_filetype(entry) != ZIP_ARCHIVE_IFREG || archive_entry_hardlink(entry) != NULL;
    archive_read_data_skip(reader->archive);
    return 1;
}

const char *ZIPArchiveReaderError(ZIPArchiveReader *reader) {
    return archive_error_string(reader->archive);
}

void ZIPArchiveReaderFree(ZIPArchiveReader *reader) {
    if (reader == NULL) return;
    archive_read_free(reader->archive);
    free(reader);
}

static void ZIPSetError(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(ZIPLastError, sizeof(ZIPLastError), format, arguments);
    va_end(arguments);
}

static int ZIPPathIsSafe(const char *path) {
    if (path == NULL || path[0] == '\0' || path[0] == '/' || path[0] == '\\') return 0;

    const char *component = path;
    for (const char *cursor = path; ; cursor++) {
        if (*cursor == '/' || *cursor == '\\' || *cursor == '\0') {
            size_t length = (size_t)(cursor - component);
            if (length == 2 && component[0] == '.' && component[1] == '.') return 0;
            if (*cursor == '\0') break;
            component = cursor + 1;
        }
    }
    return 1;
}

static int ZIPPathWasSelected(const char *path, const char *const *selectedPaths, size_t selectedCount) {
    for (size_t index = 0; index < selectedCount; index++) {
        if (selectedPaths[index] != NULL && strcmp(path, selectedPaths[index]) == 0) return 1;
    }
    return 0;
}

static int ZIPWriteEntry(archive_t *archive, int destinationFD, const char *path) {
    char *normalized = strdup(path);
    if (normalized == NULL) {
        ZIPSetError("Not enough memory.");
        return -1;
    }
    for (char *cursor = normalized; *cursor != '\0'; cursor++) {
        if (*cursor == '\\') *cursor = '/';
    }

    int currentFD = dup(destinationFD);
    if (currentFD < 0) {
        ZIPSetError("Cannot access destination: %s", strerror(errno));
        free(normalized);
        return -1;
    }

    char *savePointer = NULL;
    char *component = strtok_r(normalized, "/", &savePointer);
    if (component == NULL) {
        ZIPSetError("Invalid archive path.");
        close(currentFD);
        free(normalized);
        return -1;
    }

    while (component != NULL) {
        char *next = strtok_r(NULL, "/", &savePointer);
        if (next == NULL) {
            int outputFD = openat(currentFD, component, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0644);
            if (outputFD < 0) {
                ZIPSetError("Cannot create %s: %s", path, strerror(errno));
                close(currentFD);
                free(normalized);
                return -1;
            }

            char buffer[64 * 1024];
            int failed = 0;
            for (;;) {
                ssize_t bytesRead = archive_read_data(archive, buffer, sizeof(buffer));
                if (bytesRead == 0) break;
                if (bytesRead < 0) {
                    const char *message = archive_error_string(archive);
                    ZIPSetError("Cannot read %s: %s", path, message != NULL ? message : "archive error");
                    failed = 1;
                    break;
                }

                ssize_t written = 0;
                while (written < bytesRead) {
                    ssize_t result = write(outputFD, buffer + written, (size_t)(bytesRead - written));
                    if (result <= 0) {
                        ZIPSetError("Cannot write %s: %s", path, result < 0 ? strerror(errno) : "zero-byte write");
                        failed = 1;
                        break;
                    }
                    written += result;
                }
                if (failed) break;
            }

            if (close(outputFD) != 0 && !failed) {
                ZIPSetError("Cannot finish %s: %s", path, strerror(errno));
                failed = 1;
            }
            if (failed) unlinkat(currentFD, component, 0);
            close(currentFD);
            free(normalized);
            return failed ? -1 : 0;
        }

        if (mkdirat(currentFD, component, 0755) != 0 && errno != EEXIST) {
            ZIPSetError("Cannot create folder for %s: %s", path, strerror(errno));
            close(currentFD);
            free(normalized);
            return -1;
        }
        int nextFD = openat(currentFD, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (nextFD < 0) {
            ZIPSetError("Unsafe or inaccessible folder for %s: %s", path, strerror(errno));
            close(currentFD);
            free(normalized);
            return -1;
        }
        close(currentFD);
        currentFD = nextFD;
        component = next;
    }

    close(currentFD);
    free(normalized);
    ZIPSetError("Invalid archive path.");
    return -1;
}

int ZIPArchiveExtractSelected(
    const char *archivePath,
    const char *destinationPath,
    const char *const *selectedPaths,
    size_t selectedCount
) {
    ZIPLastError[0] = '\0';
    if (archivePath == NULL || destinationPath == NULL || selectedPaths == NULL || selectedCount == 0) {
        ZIPSetError("Nothing selected.");
        return -1;
    }
    for (size_t index = 0; index < selectedCount; index++) {
        if (!ZIPPathIsSafe(selectedPaths[index])) {
            ZIPSetError("Unsafe archive path.");
            return -1;
        }
    }

    archive_t *archive = archive_read_new();
    if (archive == NULL) {
        ZIPSetError("Cannot initialize archive reader.");
        return -1;
    }
    archive_read_support_filter_all(archive);
    archive_read_support_format_all(archive);
    if (archive_read_open_filename(archive, archivePath, 10240) < ZIP_ARCHIVE_OK) {
        const char *message = archive_error_string(archive);
        ZIPSetError("Cannot open archive: %s", message != NULL ? message : "archive error");
        archive_read_free(archive);
        return -1;
    }

    int destinationFD = open(destinationPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (destinationFD < 0) {
        ZIPSetError("Cannot open destination: %s", strerror(errno));
        archive_read_free(archive);
        return -1;
    }

    size_t extractedCount = 0;
    archive_entry_t *entry = NULL;
    int result = 0;
    for (;;) {
        int status = archive_read_next_header(archive, &entry);
        if (status == ZIP_ARCHIVE_EOF) break;
        if (status < ZIP_ARCHIVE_OK) {
            const char *message = archive_error_string(archive);
            ZIPSetError("Cannot read archive: %s", message != NULL ? message : "archive error");
            result = -1;
            break;
        }

        const char *path = archive_entry_pathname_utf8(entry);
        if (path == NULL) path = archive_entry_pathname(entry);
        if (path == NULL || !ZIPPathWasSelected(path, selectedPaths, selectedCount)) {
            archive_read_data_skip(archive);
            continue;
        }
        if (!ZIPPathIsSafe(path) || archive_entry_filetype(entry) != ZIP_ARCHIVE_IFREG || archive_entry_hardlink(entry) != NULL) {
            ZIPSetError("Unsafe archive entry: %s", path);
            result = -1;
            break;
        }
        if (ZIPWriteEntry(archive, destinationFD, path) != 0) {
            result = -1;
            break;
        }
        extractedCount++;
    }

    close(destinationFD);
    archive_read_free(archive);
    if (result == 0 && extractedCount != selectedCount) {
        ZIPSetError("Some selected files were not found in the archive.");
        result = -1;
    }
    return result == 0 ? (int)extractedCount : -1;
}

const char *ZIPArchiveLastError(void) {
    return ZIPLastError;
}
