"""Video -> 3D joint tracks, on the CPU.

Reads any video file and writes one JSON of per-frame 3D joint positions using
MediaPipe Pose. No graphics card and no account: the laptop this was built for
has integrated Intel graphics with no CUDA, which rules out the GVHMR/WHAM class
of tools entirely. MediaPipe runs the whole thing on the processor.

Output feeds tools/mocap/retarget_to_rig.py, which turns these tracks into bone
rotations on the player rig.

    python video_to_joints.py --video clip.mp4 --out clip_joints.json [--preview]

A note on sources: film it yourself, or use footage you have the rights to.
Pulling motion out of broadcast footage and shipping it in a product is a rights
problem, not a technical one.
"""
import argparse, json, math, os, sys

import cv2
import mediapipe as mp
import numpy as np

# The joints the retargeter needs, by MediaPipe landmark index.
JOINTS = {
    "nose": 0,
    "l_shoulder": 11, "r_shoulder": 12,
    "l_elbow": 13, "r_elbow": 14,
    "l_wrist": 15, "r_wrist": 16,
    "l_hip": 23, "r_hip": 24,
    "l_knee": 25, "r_knee": 26,
    "l_ankle": 27, "r_ankle": 28,
    "l_foot": 31, "r_foot": 32,
}


def smooth(track, window):
    """Moving average over frames. Raw per-frame pose estimates jitter; without
    this the retargeted skeleton buzzes."""
    if window < 2 or len(track) < window:
        return track
    arr = np.asarray(track, dtype=np.float32)
    pad = window // 2
    padded = np.pad(arr, ((pad, pad), (0, 0)), mode="edge")
    kernel = np.ones(window, dtype=np.float32) / float(window)
    out = np.empty_like(arr)
    for axis in range(arr.shape[1]):
        out[:, axis] = np.convolve(padded[:, axis], kernel, mode="valid")[: len(arr)]
    return out.tolist()


def extract(video_path, smooth_window=5, preview_dir=None):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise SystemExit(f"cannot open video: {video_path}")
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0

    pose = mp.solutions.pose.Pose(
        static_image_mode=False,
        model_complexity=2,          # heaviest CPU model - accuracy over speed
        smooth_landmarks=True,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    )

    tracks = {name: [] for name in JOINTS}
    visibility = {name: [] for name in JOINTS}
    frames = 0
    missed = 0

    while True:
        ok, frame = cap.read()
        if not ok:
            break
        result = pose.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
        lms = result.pose_world_landmarks
        if lms is None:
            missed += 1
            for name in JOINTS:
                last = tracks[name][-1] if tracks[name] else [0.0, 0.0, 0.0]
                tracks[name].append(last)
                visibility[name].append(0.0)
        else:
            for name, idx in JOINTS.items():
                lm = lms.landmark[idx]
                # MediaPipe world space is metres with X right, Y DOWN, Z toward
                # the camera. Blender is X right, Y forward, Z up.
                tracks[name].append([lm.x, lm.z, -lm.y])
                visibility[name].append(float(lm.visibility))
        if preview_dir and frames % 15 == 0 and lms is not None:
            os.makedirs(preview_dir, exist_ok=True)
            mp.solutions.drawing_utils.draw_landmarks(
                frame, result.pose_landmarks, mp.solutions.pose.POSE_CONNECTIONS)
            cv2.imwrite(os.path.join(preview_dir, f"pose_{frames:05d}.png"), frame)
        frames += 1

    cap.release()
    pose.close()

    if frames == 0:
        raise SystemExit("video contained no frames")

    for name in tracks:
        tracks[name] = smooth(tracks[name], smooth_window)

    tracked = frames - missed
    print(f"AUDIT: frames={frames} tracked={tracked} "
          f"({100.0 * tracked / frames:.1f}%) fps={fps:.2f}")
    if tracked == 0:
        raise SystemExit("no person found in any frame")

    return {"fps": fps, "frames": frames, "joints": tracks, "visibility": visibility}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--video", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--smooth", type=int, default=5)
    ap.add_argument("--preview", action="store_true")
    args = ap.parse_args()

    data = extract(args.video, args.smooth,
                   os.path.join(os.path.dirname(args.out), "pose_preview") if args.preview else None)
    with open(args.out, "w") as fh:
        json.dump(data, fh)
    print(f"AUDIT: wrote {args.out} ({os.path.getsize(args.out)} bytes)")


if __name__ == "__main__":
    main()