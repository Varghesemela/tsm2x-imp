#ifndef _HIP_ERROR_CUH
#define _HIP_ERROR_CUH

#include "libwb/wb.h"
#include <hip/hip_runtime.h>

#define wbCheck(stmt)                                                     \
  do {                                                                    \
    hipError_t err = stmt;                                               \
    if (err != hipSuccess) {                                             \
      wbLog(ERROR, "HIP error: ", hipGetErrorString(err));              \
      wbLog(ERROR, "Failed to run stmt ", #stmt);                         \
      return -1;                                                          \
    }                                                                     \
  } while (0)

#endif