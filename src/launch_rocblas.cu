/**
 * rocblas wrapper for different matrix types
 * by Cody Rivera, 2019-2020
 */

#include "rocblas.h"
#include "launch_rocblas.cuh"


// float specialization
template <>
rocblasStatus_t launchrocblas(rocblasHandle_t handle, float& one, float& zero,
                            const float* devA, const float* devB, float* devC,
                            const unsigned int m, const unsigned int n, 
                            const unsigned int k) {
    return rocblasGemmEx(handle, rocblas_OP_N, rocblas_OP_N, m, n, k, &one,
                        devA, CUDA_R_32F, m, devB, CUDA_R_32F, k, &zero,
                        devC, CUDA_R_32F, m, CUDA_R_32F,
                        rocblas_GEMM_DEFAULT);
}

// double specialization
template <>
rocblasStatus_t launchrocblas(rocblasHandle_t handle, double& one, double& zero,
                            const double* devA, const double* devB, double* devC,
                            const unsigned int m, const unsigned int n, 
                            const unsigned int k) {
    return rocblasGemmEx(handle, rocblas_OP_N, rocblas_OP_N, m, n, k, &one,
                        devA, CUDA_R_64F, m, devB, CUDA_R_64F, k, &zero,
                        devC, CUDA_R_64F, m, CUDA_R_64F,
                        rocblas_GEMM_DEFAULT);
}
 