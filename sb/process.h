#pragma once

#include <stdbool.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <string.h>

// The injector and MobileSafety may be iOS-format libraries inside SurfBoard.
static inline bool EKIsSurfBoard(void)
{
    char path[PATH_MAX] = {0};
    uint32_t size = sizeof(path);
    return _NSGetExecutablePath(path, &size) == 0
        && strcmp(path, "/System/Library/CoreServices/SurfBoard.app/SurfBoard") == 0;
}
