/*
 * Copyright (c) 2025, NVIDIA CORPORATION. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of NVIDIA CORPORATION nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <cublasLt.h>
#include <iostream>
using namespace std;

#include "helpers.h"
#include "sample_cublasLt_LtMxfp8Matmul.h"

/// Sample wrapper executing mxfp8 matmul with cublasLtMatmul, with addition of per-tensor scaling, and
/// the workspace to support split-K algorithms.
///
/// pointer mode is for alpha and beta is always host, to change it configure the appropriate matmul descriptor
/// attribute matmul is not using cublas handle's configuration of math mode, here tensor ops are implicitly allowed; to
/// change this configure appropriate attribute in the preference handle
void LtMxfp8Matmul(cublasLtHandle_t ltHandle,
                 cublasOperation_t transa,
                 cublasOperation_t transb,
                 int m,
                 int n,
                 int k,
                 const float *alpha, /* host pointer */
                 const __nv_fp8_e8m0 *a_scale, /* device pointer */
                 const __nv_fp8_e4m3 *A,
                 int lda,
                 const __nv_fp8_e8m0 *b_scale, /* device pointer */
                 const __nv_fp8_e4m3 *B,
                 int ldb,
                 const float *beta, /* host pointer */
                 const __nv_fp8_e8m0 *c_scale, /* device pointer */
                 __nv_bfloat16 *C,
                 int ldc,
                 __nv_fp8_e4m3 *D,
                 int ldd,
                 __nv_fp8_e8m0 *d_out_scale, /* device pointer */
                 void *workspace,
                 size_t workspaceSize,
                 cublasLtMatmulMatrixScale_t AScaleMode,
                 cublasLtMatmulMatrixScale_t BScaleMode,
                 cublasLtMatmulMatrixScale_t CScaleMode,
                 cublasLtMatmulMatrixScale_t DOutScaleMode) {
    cublasLtMatmulDesc_t operationDesc = NULL;
    cublasLtMatrixLayout_t Adesc = NULL, Bdesc = NULL, Cdesc = NULL, Ddesc = NULL;
    cublasLtMatmulPreference_t preference = NULL;

    int returnedResults                             = 0;
    cublasLtMatmulHeuristicResult_t heuristicResult = {};

    // create operation desciriptor; see cublasLtMatmulDescAttributes_t for details about defaults; here we just need to
    // set the transforms for A and B
    checkCublasStatus(cublasLtMatmulDescCreate(&operationDesc, CUBLAS_COMPUTE_32F, CUDA_R_32F));
    checkCublasStatus(cublasLtMatmulDescSetAttribute(operationDesc, CUBLASLT_MATMUL_DESC_TRANSA, &transa, sizeof(transa)));
    checkCublasStatus(cublasLtMatmulDescSetAttribute(operationDesc, CUBLASLT_MATMUL_DESC_TRANSB, &transb, sizeof(transb)));


    // set block scaling mode
    checkCublasStatus(cublasLtMatmulDescSetAttribute(operationDesc, CUBLASLT_MATMUL_DESC_A_SCALE_MODE, &AScaleMode, sizeof(AScaleMode)));
    checkCublasStatus(cublasLtMatmulDescSetAttribute(operationDesc, CUBLASLT_MATMUL_DESC_B_SCALE_MODE, &BScaleMode, sizeof(BScaleMode)));
    checkCublasStatus(cublasLtMatmulDescSetAttribute(operationDesc, CUBLASLT_MATMUL_DESC_D_OUT_SCALE_MODE, &DOutScaleMode, sizeof(DOutScaleMode)));

    // set scaling factors
    checkCublasStatus(cublasLtMatmulDescSetAttribute(operationDesc, CUBLASLT_MATMUL_DESC_A_SCALE_POINTER, &a_scale, sizeof(a_scale)));
    checkCublasStatus(cublasLtMatmulDescSetAttribute(operationDesc, CUBLASLT_MATMUL_DESC_B_SCALE_POINTER, &b_scale, sizeof(b_scale)));
    checkCublasStatus(cublasLtMatmulDescSetAttribute(operationDesc, CUBLASLT_MATMUL_DESC_D_OUT_SCALE_POINTER, &d_out_scale, sizeof(d_out_scale)));

    // create matrix descriptors, we are good with the details here so no need to set any extra attributes
    // table of supported type combinations can be found in the documentation: https://docs.nvidia.com/cuda/cublas/index.html#cublasltmatmul
    checkCublasStatus(cublasLtMatrixLayoutCreate(&Adesc, CUDA_R_8F_E4M3, transa == CUBLAS_OP_N ? m : k, transa == CUBLAS_OP_N ? k : m, lda));
    checkCublasStatus(cublasLtMatrixLayoutCreate(&Bdesc, CUDA_R_8F_E4M3, transb == CUBLAS_OP_N ? k : n, transb == CUBLAS_OP_N ? n : k, ldb));
    checkCublasStatus(cublasLtMatrixLayoutCreate(&Cdesc, CUDA_R_16BF, m, n, ldc));
    checkCublasStatus(cublasLtMatrixLayoutCreate(&Ddesc, CUDA_R_8F_E4M3, m, n, ldd));

    // create preference handle; here we could use extra attributes to disable tensor ops or to make sure algo selected
    // will work with badly aligned A, B, C; here for simplicity we just assume A,B,C are always well aligned (e.g.
    // directly come from cudaMalloc)
    checkCublasStatus(cublasLtMatmulPreferenceCreate(&preference));
    checkCublasStatus(cublasLtMatmulPreferenceSetAttribute(preference, CUBLASLT_MATMUL_PREF_MAX_WORKSPACE_BYTES, &workspaceSize, sizeof(workspaceSize)));

    // we just need the best available heuristic to try and run matmul. There is no guarantee this will work, e.g. if A
    // is badly aligned, you can request more (e.g. 32) algos and try to run them one by one until something works
    checkCublasStatus(cublasLtMatmulAlgoGetHeuristic(ltHandle, operationDesc, Adesc, Bdesc, Cdesc, Ddesc, preference, 1, &heuristicResult, &returnedResults));

    if (returnedResults == 0) {
        checkCublasStatus(CUBLAS_STATUS_NOT_SUPPORTED);
    }

int iters=2000;
int warmup=500;
int batchCount=1;
for (int ii=0; ii < warmup; ++ii){
    checkCublasStatus(cublasLtMatmul(ltHandle,
                                     operationDesc,
                                     alpha,
                                     A,
                                     Adesc,
                                     B,
                                     Bdesc,
                                     &beta,
                                     C,
                                     Cdesc,
                                     D,
                                     Ddesc,
                                     &heuristicResult.algo,
                                     workspace,
                                     workspaceSize,
                                     0));
}
printf("%d iters warmup finished. \n", warmup);

  cudaEvent_t start, stop;
  cudaEventCreate(&start);
  cudaEventCreate(&stop);
  cudaEventRecord(start, 0);
  for (int ii=0; ii < iters; ++ii){
    checkCublasStatus(cublasLtMatmul(ltHandle,
                                     operationDesc,
                                     alpha,
                                     A,
                                     Adesc,
                                     B,
                                     Bdesc,
                                     &beta,
                                     C,
                                     Cdesc,
                                     D,
                                     Ddesc,
                                     &heuristicResult.algo,
                                     workspace,
                                     workspaceSize,
                                     0));
}
    cudaEventRecord(stop,0);
    cudaEventSynchronize(stop);
    float elapsed;
    cudaEventElapsedTime(&elapsed, start, stop);
    cout << "running gemm with repeats: " << iters << ", average time: " << elapsed/iters << " ms, bs=" << batchCount << ", m=" << m << ", n=" << n << ", k="<< k << ", tflops=" << 2*1e-9*m*n*k/(elapsed/iters) * batchCount << endl;   
    

    // descriptors are no longer needed as all GPU work was already enqueued
    if (preference) checkCublasStatus(cublasLtMatmulPreferenceDestroy(preference));
    if (Ddesc) checkCublasStatus(cublasLtMatrixLayoutDestroy(Ddesc));
    if (Cdesc) checkCublasStatus(cublasLtMatrixLayoutDestroy(Cdesc));
    if (Bdesc) checkCublasStatus(cublasLtMatrixLayoutDestroy(Bdesc));
    if (Adesc) checkCublasStatus(cublasLtMatrixLayoutDestroy(Adesc));
    if (operationDesc) checkCublasStatus(cublasLtMatmulDescDestroy(operationDesc));
}
