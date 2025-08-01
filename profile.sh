#!/bin/bash

set -e

SCRIPT_DIR=$(dirname "$(realpath $0)")

LOG_FILE="$SCRIPT_DIR/profile_log.txt"

# Define problem shapes and transpose configurations
PROBLEM_SHAPES=("16384x16384x16384" "8192x16384x16384" "1024x16384x16384")
TRANSPOSE_VALUES=("0" "1")

# Define executables to profile
EXECUTABLES=(
    "$SCRIPT_DIR/cuBLASLt/LtHSHgemmStridedBatchSimple/build/sample_cublasLt_LtHSHgemmStridedBatchSimple"
    "$SCRIPT_DIR/cuBLASLt/LtMxfp8Matmul/build/sample_cublasLt_LtMxfp8Matmul"
)

RANDOM_MAX_VALUES=("0.5" "5")
FREQ_VALUES=("oob" "1305" "1500")

# GPU settings
GPU_ID=2
echo "export CUDA_VISIBLE_DEVICES=$GPU_ID" | tee -a "$LOG_FILE"
export CUDA_VISIBLE_DEVICES=$GPU_ID

# Add --dry option
DRY_RUN=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry)
      DRY_RUN=1
      LOG_FILE="$SCRIPT_DIR/profile_cmd.txt"
      shift
      ;;
    *)
      echo "Unknown parameter: $1"
      exit 1
      ;;
  esac
done

: > "$LOG_FILE" # Clear the log file

# Define execute function
execute() {
  local cmd="$1"
  if [ "$DRY_RUN" -eq 0 ]; then
    echo "[cmd] $cmd" | tee -a "$LOG_FILE"
    eval "$cmd" | tee -a "$LOG_FILE" 2>&1
    echo | tee -a "$LOG_FILE"
  else
    echo "$cmd" | tee -a "$LOG_FILE"
  fi
}

wl_id=0
gpu_monitor_cmd="nvidia-smi --id=${GPU_ID} --loop-ms=100 -q -a| grep -v -e{Fan,N/A,JPEG,OFA} > nvsmi.csv"

# NVIDIA SMI logging
nvsmi_log() {
  if [ "$DRY_RUN" -eq 0 ]; then
    if [ "$1" = "start" ]; then
      echo "Starting GPU monitoring: $gpu_monitor_cmd"
      eval "$gpu_monitor_cmd" &
    elif [ "$1" = "stop" ]; then
      echo "Stopping GPU monitoring"
      pkill -f nvidia-smi
      sleep 5
    fi
  fi
}

# Rename log file
rename_log() {
  mv "$1" "$2"
}

# Profile each combination of problem shape, transpose values, random max, and frequency
for EXECUTABLE in "${EXECUTABLES[@]}"; do
  for PROBLEM_SHAPE in "${PROBLEM_SHAPES[@]}"; do
    for TRANS_A in "${TRANSPOSE_VALUES[@]}"; do
      for TRANS_B in "${TRANSPOSE_VALUES[@]}"; do
        for RANDOM_MAX in "${RANDOM_MAX_VALUES[@]}"; do
          for FREQ in "${FREQ_VALUES[@]}"; do
            if [[ "$FREQ" == "oob" ]]; then
              execute "nvidia-smi --reset-gpu-clocks --id=\"$GPU_ID\""
            else
              execute "nvidia-smi --id=\"$GPU_ID\" --lock-gpu-clocks=\"$FREQ\",\"$FREQ\""
            fi

            nvsmi_log start
            cmd="PROBLEM_SHAPE=$PROBLEM_SHAPE TRANS_A=$TRANS_A TRANS_B=$TRANS_B RANDOM_MAX=$RANDOM_MAX ENABLE_PROFILE=1 \"$EXECUTABLE\""
            execute "$cmd"
            nvsmi_log stop

            rename_log nvsmi.csv "workload${wl_id}_nvsmi.txt"
            echo "Renamed nvsmi.csv to workload${wl_id}_nvsmi.txt" | tee -a "$LOG_FILE"
            wl_id=$((wl_id + 1))

            if [[ "$FREQ" != "oob" ]]; then
              execute "nvidia-smi --reset-gpu-clocks --id=\"$GPU_ID\""
            fi
          done
        done
      done
    done
  done
done

# Special handling for nvfp4_gemm with two problem shapes and frequencies
NVFP4_EXECUTABLE="$SCRIPT_DIR/cuBLASLt/LtNvfp4Matmul/build/sample_cublasLt_LtNvfp4Matmul"
if [[ -f "$NVFP4_EXECUTABLE" ]]; then
  for PROBLEM_SHAPE in "${PROBLEM_SHAPES[@]}"; do
    for FREQ in "${FREQ_VALUES[@]}"; do
      if [[ "$FREQ" == "oob" ]]; then
        execute "nvidia-smi --reset-gpu-clocks --id=\"$GPU_ID\""
      else
        execute "nvidia-smi --id=\"$GPU_ID\" --lock-gpu-clocks=\"$FREQ\",\"$FREQ\""
      fi

      nvsmi_log start
      cmd="PROBLEM_SHAPE=$PROBLEM_SHAPE FREQ=$FREQ TRANS_A=1 TRANS_B=0 RANDOM_MAX=6 ENABLE_PROFILE=1 PROFILE_ITER="1000,20000" \"$NVFP4_EXECUTABLE\""
      execute "$cmd"
      nvsmi_log stop

      rename_log nvsmi.csv "workload${wl_id}_nvsmi.txt"
      echo "Renamed nvsmi.csv to workload${wl_id}_nvsmi.txt" | tee -a "$LOG_FILE"
      wl_id=$((wl_id + 1))

      if [[ "$FREQ" != "oob" ]]; then
        execute "nvidia-smi --reset-gpu-clocks --id=\"$GPU_ID\""
      fi
    done
  done
fi

echo "Profiling completed. Results are logged in $LOG_FILE."
