#!/usr/bin/env python3
"""Compare two equal-rate multichannel WAV files with per-channel alignment."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import correlate, correlation_lags


CHANNEL_LABELS = (
    "FL",
    "FR",
    "FC",
    "LFE",
    "BL",
    "BR",
    "SL",
    "SR",
    "TFL",
    "TFR",
    "TBL",
    "TBR",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("candidate", type=Path)
    parser.add_argument("reference", type=Path)
    parser.add_argument("--max-lag", type=int, default=4096)
    parser.add_argument("--decimation", type=int, default=16)
    parser.add_argument("--start", type=float, default=0.0, help="window start in seconds")
    parser.add_argument("--duration", type=float, help="window duration in seconds")
    return parser.parse_args()


def load(path: Path) -> tuple[int, np.ndarray]:
    sample_rate, pcm = wavfile.read(path)
    if pcm.ndim == 1:
        pcm = pcm[:, np.newaxis]
    if np.issubdtype(pcm.dtype, np.integer):
        scale = max(abs(np.iinfo(pcm.dtype).min), np.iinfo(pcm.dtype).max)
        pcm = pcm.astype(np.float64) / scale
    else:
        pcm = pcm.astype(np.float64)
    return sample_rate, pcm


def overlap(candidate: np.ndarray, reference: np.ndarray, lag: int) -> tuple[np.ndarray, np.ndarray]:
    if lag >= 0:
        length = min(candidate.size - lag, reference.size)
        return candidate[lag : lag + length], reference[:length]
    length = min(candidate.size, reference.size + lag)
    return candidate[:length], reference[-lag : -lag + length]


def correlation(candidate: np.ndarray, reference: np.ndarray, lag: int) -> float:
    candidate, reference = overlap(candidate, reference, lag)
    denominator = math.sqrt(float(candidate @ candidate) * float(reference @ reference))
    return float(candidate @ reference) / denominator if denominator else 0.0


def best_lag(
    candidate: np.ndarray,
    reference: np.ndarray,
    max_lag: int,
    decimation: int,
) -> tuple[int, float]:
    decimated_candidate = candidate[::decimation]
    decimated_reference = reference[::decimation]
    values = correlate(decimated_candidate, decimated_reference, mode="full", method="fft")
    lags = correlation_lags(decimated_candidate.size, decimated_reference.size, mode="full")
    limit = max_lag // decimation
    allowed = np.abs(lags) <= limit
    coarse = int(lags[allowed][np.argmax(values[allowed])]) * decimation

    candidates = range(max(-max_lag, coarse - decimation), min(max_lag, coarse + decimation) + 1)
    return max(((lag, correlation(candidate, reference, lag)) for lag in candidates), key=lambda item: item[1])


def db(value: float) -> float:
    return 20.0 * math.log10(max(value, np.finfo(float).tiny))


def main() -> None:
    args = parse_args()
    candidate_rate, candidate = load(args.candidate)
    reference_rate, reference = load(args.reference)
    if candidate_rate != reference_rate:
        raise SystemExit(f"sample-rate mismatch: {candidate_rate} != {reference_rate}")
    if candidate.shape[1] != reference.shape[1]:
        raise SystemExit(f"channel-count mismatch: {candidate.shape[1]} != {reference.shape[1]}")

    start = round(args.start * candidate_rate)
    if start < 0:
        raise SystemExit("--start must be non-negative")
    stop = None if args.duration is None else start + round(args.duration * candidate_rate)
    candidate = candidate[start:stop]
    reference = reference[start:stop]
    if not candidate.size or not reference.size:
        raise SystemExit("selected comparison window is empty")

    print(f"candidate={args.candidate}")
    print(f"reference={args.reference}")
    print(f"window_start={args.start:.6f}s window_duration={args.duration}")
    print("channel\tlag_samples\tlag_ms\tcorr\tcandidate_rms_db\treference_rms_db\tgain_fit_db\tsnr_db")
    for channel_index in range(candidate.shape[1]):
        candidate_channel = candidate[:, channel_index]
        reference_channel = reference[:, channel_index]
        lag, corr = best_lag(
            candidate_channel,
            reference_channel,
            args.max_lag,
            args.decimation,
        )
        aligned_candidate, aligned_reference = overlap(candidate_channel, reference_channel, lag)
        candidate_energy = float(aligned_candidate @ aligned_candidate)
        gain = (
            float(aligned_candidate @ aligned_reference) / candidate_energy
            if candidate_energy
            else 0.0
        )
        residual = aligned_reference - aligned_candidate * gain
        reference_energy = float(aligned_reference @ aligned_reference)
        residual_energy = float(residual @ residual)
        snr = 10.0 * math.log10(reference_energy / residual_energy) if residual_energy else math.inf
        label = CHANNEL_LABELS[channel_index] if channel_index < len(CHANNEL_LABELS) else str(channel_index)
        print(
            f"{label}\t{lag}\t{lag * 1000.0 / candidate_rate:.3f}\t{corr:.6f}\t"
            f"{db(math.sqrt(candidate_energy / aligned_candidate.size)):.3f}\t"
            f"{db(math.sqrt(reference_energy / aligned_reference.size)):.3f}\t"
            f"{db(abs(gain)):.3f}\t{snr:.3f}"
        )


if __name__ == "__main__":
    main()
