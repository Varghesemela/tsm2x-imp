/**
 * External interfaces to CUBLAS
 * by Cody Rivera, 2019-2020
 */

#ifndef _LAUNCH_ROCBLAS_CUH
#define _LAUNCH_ROCBLAS_CUH
 
#include <rocblas/rocblas.h>

#define rocblasErrchk(ans) { rocblasAssert((ans), __FILE__, __LINE__); }
inline void rocblasAssert(rocblas_status code, const char *file, int line) {
    if (code != rocblas_status_success) {
        fprintf(stderr, "rocBLAS error: %d %s %d\n", code, file, line);
        exit(code);
    }
}

template <typename FloatType>
rocblas_status launchRocblas(rocblas_handle handle, FloatType alpha, FloatType beta,
                             const FloatType *A, const FloatType *B, FloatType *C,
                             int m, int n, int k) {
    return rocblas_gemm<FloatType>(handle, rocblas_operation_none, rocblas_operation_none,
                                   m, n, k, &alpha, A, m, B, k, &beta, C, m);
}

template <>
rocblas_status launchRocblas<float>(rocblas_handle handle, float alpha, float beta,
                                    const float *A, const float *B, float *C,
                                    int m, int n, int k) {
    return rocblas_sgemm(handle, rocblas_operation_none, rocblas_operation_none,
                         m, n, k, &alpha, A, m, B, k, &beta, C, m);
}

template <>
rocblas_status launchRocblas<double>(rocblas_handle handle, double alpha, double beta,
                                     const double *A, const double *B, double *C,
                                     int m, int n, int k) {
    return rocblas_dgemm(handle, rocblas_operation_none, rocblas_operation_none,
                         m, n, k, &alpha, A, m, B, k, &beta, C, m);
}

#endif