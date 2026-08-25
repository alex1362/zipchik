#ifndef ZIP_ARCHIVE_BRIDGE_H
#define ZIP_ARCHIVE_BRIDGE_H

#include <stddef.h>

typedef struct ZIPArchiveReader ZIPArchiveReader;

ZIPArchiveReader *ZIPArchiveReaderCreate(const char *path);
int ZIPArchiveReaderNext(ZIPArchiveReader *reader, const char **path, int *isDirectory);
const char *ZIPArchiveReaderError(ZIPArchiveReader *reader);
void ZIPArchiveReaderFree(ZIPArchiveReader *reader);

int ZIPArchiveExtractSelected(
    const char *archivePath,
    const char *destinationPath,
    const char *const *selectedPaths,
    size_t selectedCount
);
const char *ZIPArchiveLastError(void);

#endif
