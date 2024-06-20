/**
 * TSM2 and ISM2 Testbed and Evaluation Platform
 * by Cody Rivera, 2019-2020
 *
 * Usage - ./multiply [-d] [-i] matrixA matrixB matrixC
 * where -d signifies double precision, and -i signifies
 * ISM2
 */

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>

// #include "libwb/wb.h"
#include <hip/hip_runtime.h>
#include <rocblas/rocblas.h>
#include "hip_error.cuh"
#include "kernels.cuh"
#include "multiply.cuh"
#include "launch_rocblas.cuh"

// Testing Parameters -- Adjust as needed
#define EPS 1e-3
#define N_WARMUP 10
#define N_ROUNDS 100

/**
 * Testbed helper functions.
 */
// Based on
// https://randomascii.wordpress.com/2012/02/25/comparing-floating-point-numbers-2012-edition/
bool approxEqual(double A, double B, double maxRelDiff = EPS) {
    // Calculate the difference.
    double diff = fabs(A - B);
    A = fabs(A);
    B = fabs(B);
    // Find the largest
    double largest = (B > A) ? B : A;

    if (diff <= largest * maxRelDiff) return true;
    return false;
}

template <typename FloatType>
bool matrixCompare(const FloatType* A, const FloatType* B, unsigned int m,
                   unsigned int n, unsigned int& iFail, unsigned int& jFail) {
    FloatType aVal, bVal;
    bool b = true;
    // Cache-friendly comparison pattern
    for (unsigned int j = 0; j < n && b; j++) {
        for (unsigned int i = 0; i < m && b; i++) {
            aVal = A[i + (j * m)];
            bVal = B[i + (j * m)];
            if (!approxEqual(aVal, bVal, EPS)) {
                iFail = i;
                jFail = j;
                b = false;
            }
        }
    }
    return b;
}

template <typename FloatType>
void reportTestSuccess(const char* testName, double GFLOPs) {
    printf("%s succeeded: %g GFLOPs, %g GFLOPs acc. for transfers\n", testName,
           GFLOPs);
}

template <typename FloatType>
void reportTestFailure(const char* testName, const FloatType* orig,
                       const FloatType* cand, unsigned int leadDim,
                       unsigned int iFail, unsigned int jFail) {
    double oVal = (double)orig[iFail + (jFail * leadDim)];
    double cVal = (double)cand[iFail + (jFail * leadDim)];
    fprintf(stderr,
            "%s failed: Original[%u, %u] = %.6f != Candidate[%u, %u] = %.6f\n",
            testName, iFail, jFail, oVal, iFail, jFail, cVal);
}

template <typename FloatType>
double getGFLOPs(double time, unsigned int m, unsigned int n, unsigned int k) {
    double instCount = ((double)m * (double)n * (double)k) / 1e9;
    double timeSeconds = time / 1000;
    return instCount / timeSeconds;
}

/**
 * Kernel launch wrapper. Runs both rocBLAS and TSM2/ISM2, for evaluation
 * purposes.
 */
template <typename FloatType>
bool runKernels(const FloatType* A, const FloatType* B, FloatType* C,
                const unsigned int m, const unsigned int n,
                const unsigned int k, const bool runIsm2) {
    // Candidate for C -- Used by GPU kernels
    FloatType* candC;
    // Device memory
    FloatType *devA, *devB, *devC;
    // Events used for timing
    hipEvent_t start, end, startTotal, endTotal;
    float time, timeTotal;

    printf("Multiplying matrix A[%u, %u] by matrix B[%u, %u]\n\n", m, k, k, n);

    // Change test name depending on runIsm2
    const char* testName = "TSM2 Kernel Test";
    if (runIsm2) {
        testName = "ISM2 Kernel Test";
    }

    // Allocates new memory
    candC = (FloatType*)malloc(m * n * sizeof(FloatType));
    if (candC == NULL) {
        fprintf(stderr, "Not enough memory\n");
        return false;
    }

    hipMalloc((FloatType**)&devA, m * k * sizeof(FloatType));
    hipMalloc((FloatType**)&devB, k * n * sizeof(FloatType));
    hipMalloc((FloatType**)&devC, m * n * sizeof(FloatType));

    // Inits hip events
    hipEventCreate(&start);
    hipEventCreate(&end);
    hipEventCreate(&startTotal);
    hipEventCreate(&endTotal);

    
    // Runs rocBLAS call
    rocblas_handle handle;
    rocblas_create_handle(&handle);

    FloatType one = 1;
    FloatType zero = 0;

    
    hipEventRecord(startTotal);

    // hip Memory Copy
    
    hipMemcpy(devA, A, m * k * sizeof(FloatType), hipMemcpyHostToDevice);
    hipMemcpy(devB, B, k * n * sizeof(FloatType), hipMemcpyHostToDevice);

    for (int i = 0; i < N_WARMUP; ++i) {
        launchRocblas<FloatType>(handle, one, zero, devA, devB, devC, m, n, k);
    }
    
    hipEventRecord(start);
    for (int i = 0; i < N_ROUNDS; ++i) {
        launchRocblas<FloatType>(handle, one, zero, devA, devB, devC, m, n, k);
    }
    hipEventRecord(end);

    // Copies result back
    
    hipMemcpy(C, devC, m * n * sizeof(FloatType), hipMemcpyDeviceToHost);

    hipEventRecord(endTotal);
    hipDeviceSynchronize();
    hipEventElapsedTime(&time, start, end);
    hipEventElapsedTime(&timeTotal, startTotal, endTotal);
    time /= N_ROUNDS;
    timeTotal /= N_ROUNDS;

    reportTestSuccess<FloatType>("rocBLAS Test", getGFLOPs<FloatType>(time, m, n, k));

    rocblas_destroy_handle(handle);
    

    // Runs kernel
    // Failure flag
    bool status;
    // Failure indices
    unsigned int iFail, jFail;

    // Clear result matrix
    hipMemset(devC, 0, m * n * sizeof(FloatType));
    hipEventRecord(startTotal);

    // hip Memory Copy
    
    hipMemcpy(devA, A, m * k * sizeof(FloatType), hipMemcpyHostToDevice);

    hipMemcpy(devB, B, k * n * sizeof(FloatType), hipMemcpyHostToDevice);

    for (int i = 0; i < N_WARMUP; ++i) {
        hipMemset(devC, 0, m * n * sizeof(FloatType));
        if (runIsm2) {
            launchKernelIsm2(devA, devB, devC, m, n, k);
        } else {
            launchKernelTsm2(devA, devB, devC, m, n, k);
        }
    }
    
    hipEventRecord(start);
    for (int i = 0; i < N_ROUNDS; ++i) {
        hipMemset(devC, 0, m * n * sizeof(FloatType));
        if (runIsm2) {
            launchKernelIsm2(devA, devB, devC, m, n, k);
        } else {
            launchKernelTsm2(devA, devB, devC, m, n, k);
        }
    }
    hipGetLastError();
    hipEventRecord(end);

    // Copies result back
    hipMemcpy(candC, devC, m * n * sizeof(FloatType),
                          hipMemcpyDeviceToHost);

    hipEventRecord(endTotal);
    hipDeviceSynchronize();
    hipEventElapsedTime(&time, start, end);
    hipEventElapsedTime(&timeTotal, startTotal, endTotal);
    time /= N_ROUNDS;
    timeTotal /= N_ROUNDS;
    
    status = matrixCompare<FloatType>(C, candC, m, n, iFail, jFail);
    if (status) {
        reportTestSuccess<FloatType>(testName,
                                  getGFLOPs<FloatType>(time, m, n, k));
    } else {
        reportTestFailure<FloatType>(testName, C, candC, m, iFail, jFail);
    }

    hipEventDestroy(start);
    hipEventDestroy(end);
    hipEventDestroy(startTotal);
    hipEventDestroy(endTotal);
    free(candC);
    hipFree(devA);
    hipFree(devB);
    hipFree(devC);

    return true;
}

/**
 * Runs testbed on specified input files. Handles file IO.
 */
template <typename FloatType>
bool runMatmul(std::istream& fileA, std::istream& fileB, std::ostream& outFile,
               bool runIsm2) {
    FloatType *A, *B, *C;
    int m, n, k, kCand;

    // Reads Matrix Sizes
    fileA.read((char*)&m, sizeof(unsigned int));
    fileA.read((char*)&k, sizeof(unsigned int));
    fileB.read((char*)&kCand, sizeof(unsigned int));
    fileB.read((char*)&n, sizeof(unsigned int));

    if (k != kCand) {
        fprintf(stderr,
                "Matrix multiplication is undefined where A's"
                "column count is not equal\n to B's row count\n\n"
                "Matrix A (%u x %u) and Matrix B (%u x %u)\n",
                m, k, kCand, n);
        return false;
    }

    // Mallocs Matrices on CPU
    A = (FloatType*)malloc((size_t)m * k * sizeof(FloatType));
    B = (FloatType*)malloc((size_t)k * n * sizeof(FloatType));
    C = (FloatType*)malloc((size_t)m * n * sizeof(FloatType));

    if (A == NULL || B == NULL || C == NULL) {
        fprintf(stderr, "Not enough memory\n");
        return false;
    }

    // Loads Data to Matrix A and B
    fileA.read((char*)A, (size_t)m * k * sizeof(FloatType));
    fileB.read((char*)B, (size_t)k * n * sizeof(FloatType));

    // Calls hip
    bool status = runKernels<FloatType>(A, B, C, m, n, k, runIsm2);
    if (!status) {
        free(A);
        free(B);
        free(C);
        return false;
    }

    // Writes output matrix
    outFile.write((const char*)&m, sizeof(unsigned int));
    outFile.write((const char*)&n, sizeof(unsigned int));
    outFile.write((const char*)C, (size_t)m * n * sizeof(FloatType));

    free(A);
    free(B);
    free(C);
    return true;
}

/**
 * Entry point
 */
int main(int argc, char** argv) {
    int fileArg[3];
    int nFiles = 0;
    bool isDouble = false;
    bool runIsm2 = false;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-d") == 0) {
            isDouble = true;
        } else if (strcmp(argv[i], "-i") == 0) {
            runIsm2 = true;
        } else {
            if (nFiles < 3) {
                fileArg[nFiles] = i;
            }
            nFiles++;
        }
    }
    if (nFiles != 3) {
        fprintf(stderr, "Usage: %s [-d] [-i] matrixA matrixB matrixC\n",
                argv[0]);
        return 1;
    }

    std::ifstream fileA(argv[fileArg[0]], std::ios::binary),
        fileB(argv[fileArg[1]], std::ios::binary);
    std::ofstream outFile(argv[fileArg[2]], std::ios::binary);
    if (!fileA) {
        fprintf(stderr, "Cannot open %s for reading\n", argv[fileArg[0]]);
        return 1;
    }
    if (!fileB) {
        fprintf(stderr, "Cannot open %s for reading\n", argv[fileArg[1]]);
        return 1;
    }
    if (!outFile) {
        fprintf(stderr, "Cannot open %s for writing\n", argv[fileArg[2]]);
        return 1;
    }
    // Runs matmul
    bool status = false;
    if (isDouble) {
        status = runMatmul<double>(fileA, fileB, outFile, runIsm2);
    } else {
        status = runMatmul<float>(fileA, fileB, outFile, runIsm2);
    }
    fileA.close();
    fileB.close();
    outFile.close();
    if (status) {
        return 0;
    } else {
        return 1;
    }
}
