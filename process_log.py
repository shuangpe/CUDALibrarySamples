#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import csv
import re

def parse_profile_log(input_file, output_file):
    with open(input_file, 'r') as f:
        lines = f.readlines()

    data = []
    current_frequency = "oob"

    for line in lines:
        # Match frequency setting without regex
        if '--lock-gpu-clocks=' in line:
            start = line.find('--lock-gpu-clocks="') + len('--lock-gpu-clocks="')
            end = line.find('","', start)
            current_frequency = line[start:end]
        elif "nvidia-smi --reset-gpu-clocks" in line:
            current_frequency = "oob"  # Reset frequency when reset command is found

        # Match profiling command
        cmd_match = re.search(r'PROBLEM_SHAPE=(\d+x\d+x\d+) FREQ=.* TRANS_A=(\d) TRANS_B=(\d) RANDOM_MAX=([\d.]+) .*?/(Lt\w+)', line)
        if cmd_match:
            problem_shape, trans_a, trans_b, random_max, application = cmd_match.groups()
            precision = "FP16"
            if application == "LtMxfp8Matmul":
                precision = "MXFP8"
            elif application == "LtNvfp4Matmul":
                precision = "NVFP4"
            trans_a = 1 - int(trans_a)

        # Match profiling result
        result_match = re.search(r'Profiling gemm with \d+ iterations .*? random_range=\[(-[\d.]+), ([\d.]+)\] .*? tflops=([\d.]+)', line)
        if result_match:
            random_range_min, random_range_max, tflops = result_match.groups()
            data.append({
                "ProblemShapeMNK": problem_shape,
                "Random Uniform Range": f"[{random_range_min}, {random_range_max}]",
                "TransposeA": trans_a,
                "TransposeB": trans_b,
                "Frequency": current_frequency,
                "Precision": precision,
                "TFLOPS": tflops
            })

    # Write to CSV
    with open(output_file, 'w', newline='') as csvfile:
        fieldnames = ["ProblemShapeMNK", "Random Uniform Range", "TransposeA", "TransposeB", "Frequency", "Precision", "TFLOPS"]
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(data)

if __name__ == "__main__":
    parse_profile_log("profile_log.txt", "output.csv")
