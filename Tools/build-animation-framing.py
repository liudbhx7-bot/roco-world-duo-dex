"""Size each APNG relative to its static artwork. Requires Python 3 and Pillow."""
import argparse
import hashlib
import json
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
from statistics import median

from PIL import Image

RESOURCES = Path(__file__).resolve().parents[1] / "RocoDex/Resources"
VISIBLE = [0] * 8 + [255] * 248


def image_bounds(image):
    return image.convert("RGBA").getchannel("A").point(VISIBLE).getbbox()


def measure(job):
    path, cache_dir = job
    cached = None
    if cache_dir:
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        cached = cache_dir / (digest + ".json")
        if cached.exists():
            return path.name, json.loads(cached.read_text())
    with Image.open(path) as image:
        samples = []
        delays = []
        for index in range(image.n_frames):
            image.seek(index)
            samples.append(image_bounds(image))
            delays.append(max(1, image.info.get("duration", 100)) / 1000)
        measurements = (image.size, samples, delays)
    if cached:
        temp = cached.with_suffix(f".{path.stem}.tmp")
        temp.write_text(json.dumps(measurements, separators=(",", ":")))
        temp.replace(cached)
    return path.name, measurements


def union(bounds):
    return (min(b[0] for b in bounds), min(b[1] for b in bounds),
            max(b[2] for b in bounds), max(b[3] for b in bounds))


def width(box):
    return box[2] - box[0]


def height(box):
    return box[3] - box[1]


def interpolate(a, b, amount):
    return tuple(x + (y - x) * amount for x, y in zip(a, b))


def include(canvas, box):
    """Enlarge an aspect-fit box just enough to include another in all layouts."""
    outer = union([canvas, box])
    scale = max(width(outer) / width(canvas), height(outer) / height(canvas))
    w, h = width(canvas) * scale, height(canvas) * scale
    x = min(max(canvas[0] - (w - width(canvas)) / 2, outer[2] - w), outer[0])
    y = min(max(canvas[1] - (h - height(canvas)) / 2, outer[3] - h), outer[1])
    return x, y, x + w, y + h


def to_json(box, size):
    w, h = size
    return dict(x=round(box[0] / w, 7), y=round(box[1] / h, 7),
                width=round(width(box) / w, 7), height=round(height(box) / h, 7))


def keyframes(boxes, size):
    """Keep the smallest changes below a fraction of a source pixel."""
    keep = {0, len(boxes) - 1}
    spans = [(0, len(boxes) - 1)]
    while spans:
        a, b = spans.pop()
        if b - a < 2:
            continue
        worst = 0
        split = a
        for i in range(a + 1, b):
            estimate = interpolate(boxes[a], boxes[b], (i-a)/(b-a))
            error = max(abs(u-v) for u, v in zip(estimate, boxes[i]))
            if error > worst:
                worst, split = error, i
        if worst > .35:
            keep.add(split)
            spans.extend([(a, split), (split, b)])
    return [dict(frame=i, **to_json(boxes[i], size)) for i in sorted(keep)]


def moving_idle(poses, delays, size, target, landing, center):
    """Follow exceptional long excursions while retaining the normal resting scale."""
    count = len(poses)
    horizon = min(count // 2, max(1, round(.22 / median(delays))))
    radius = horizon // 2
    terminal = union([box for box in (poses[0], poses[-1], landing) if box])
    poses = list(poses)
    poses[0] = poses[-1] = terminal
    view_w, view_h = target
    rects = []
    for i in range(count):
        window = [poses[j % count] for j in range(i-horizon, i+horizon+1)]
        visible = [b for b in window if b]
        l, t, r, b = union(visible) if visible else terminal
        # Leave space for antialiasing and for subpixel rounding on the device.
        pad = max(2, .012 * view_h)
        l, t, r, b = l-pad, t-pad, r+pad, b+pad
        zoom = max(1, (r-l)/view_w, (b-t)/view_h)
        w, h = view_w*zoom, view_h*zoom
        x = min(max(center[0]-w/2, r-w), l)
        y = min(max(center[1]-h/2, b-h), t)
        rects.append((x,y,x+w,y+h))
    # Every contributing rectangle encloses this pose, so their weighted
    # average still encloses it. Wrap both filters at the loop boundary.
    weights = [radius + 1 - abs(j) for j in range(-radius, radius+1)]
    mass = sum(weights)
    smooth = [tuple(sum(rects[(i+j-radius) % count][axis]*weight
                        for j, weight in enumerate(weights))/mass for axis in range(4))
              for i in range(count)]
    smooth[0] = smooth[-1] = interpolate(smooth[0], smooth[-1], .5)
    return smooth


def entry_keys(settled, clip):
    size, samples, delays = clip
    boxes = [b for b in samples if b]
    if not boxes:
        return []
    l, t, r, b = union(boxes)
    wide = include(settled, (l - 1, t - 1, r + 1, b + 1))
    expansion = [abs(a - b) for a, b in zip(settled, wide)]
    if max(expansion) < 2:
        return []
    # Stay wide for the entrance, then gently settle once the outlying movement ends.
    # The smallest blend enclosing the actual frame is a lower bound, even for a wing tip.
    needed = []
    for bounds in samples:
        distances = ([settled[0]-bounds[0], settled[1]-bounds[1],
                      bounds[2]-settled[2], bounds[3]-settled[3]] if bounds else [0]*4)
        needed.append(min(1, max([0] + [d / gap for d, gap in zip(distances, expansion) if gap > .01])))
    for i in range(len(needed) - 2, -1, -1):
        needed[i] = max(needed[i], needed[i+1])
    times = [0.]
    for d in delays[:-1]:
        times.append(times[-1] + d)
    # A decelerating tail after each movement suppresses frame-to-frame zoom changes.
    end = times[-1]
    weights = []
    for i, now in enumerate(times):
        weight = needed[i]
        for j in range(i - 1, -1, -1):
            span = min(.32, end - times[j])
            if span <= 0 or now - times[j] >= span:
                break
            remaining = 1 - (now - times[j]) / span
            weight = max(weight, needed[j] * remaining * remaining * (3 - 2 * remaining))
        weights.append(weight)
    weights[-1] = 0.
    return keyframes([interpolate(settled, wide, weight) for weight in weights], size)


def framing(artwork, entry, idle):
    ref = idle or entry
    size, samples, _ = ref
    # Entry-only forms use the resting pose just before returning to their static illustration.
    poses = [b for b in (samples if idle else samples[-max(1,len(samples)//8):]) if b]
    if not poses:
        poses = [b for b in samples if b]
    if not poses:
        raise ValueError("animation is entirely transparent")
    with Image.open(artwork) as image:
        static = image_bounds(image) or (0, 0, *image.size)
        art_w, art_h = image.size
    mw, mh = median(map(width, poses)), median(map(height, poses))
    k = max(mw / width(static), mh / height(static))
    # Match the subject's center and padding in the static illustration.
    cx = median((b[0] + b[2]) / 2 for b in poses)
    cy = median((b[1] + b[3]) / 2 for b in poses)
    x, y = cx - k * (static[0]+static[2])/2, cy - k * (static[1]+static[3])/2
    base = (x, y, x + k*art_w, y + k*art_h)
    bounds = union(poses)
    landing = None
    if entry:
        entry_size, eframes, _ = entry
        if eframes[-1]:
            ex, ey = size[0]/entry_size[0], size[1]/entry_size[1]
            landing = tuple(a*s for a,s in zip(eframes[-1],(ex,ey,ex,ey)))
            bounds = union([bounds, landing])
    pad = max(1.5, .009*max(mw,mh))
    safe = (bounds[0]-pad,bounds[1]-pad,bounds[2]+pad,bounds[3]+pad)
    # Recenter harmless free space before increasing the box to preserve flight and tails.
    w = max(width(base), width(safe))
    h = max(height(base), height(safe))
    x = min(max(base[0],safe[2]-w),safe[0])
    y = min(max(base[1],safe[3]-h),safe[1])
    settled = (x,y,x+w,y+h)
    idle_path = []
    if idle:
        # Measure apparent size in an archive slot; upright idle poses can differ
        # from wide illustrations. Only follow the action if a fixed view leaves
        # the resting creature unusually small across most of the loop.
        aspect = 520/450
        longest = median(max(width(pose),height(pose)) for pose in poses)
        static_span = max(width(static),height(static))*min(aspect/art_w,1/art_h)
        fixed_span = longest*min(aspect/width(settled),1/height(settled))
        if fixed_span < .80*static_span and any((samples[0],samples[-1],landing)):
            view_h = longest/(.94*static_span)
            idle_path = moving_idle(samples, idle[2], size, (aspect*view_h,view_h),
                                    landing, (cx,cy))
            settled = idle_path[0]
    result = to_json(settled, size)
    if idle_path:
        result["idleKeys"] = keyframes(idle_path, size)
    if entry:
        ex, ey = entry[0][0]/size[0], entry[0][1]/size[1]
        entry_box = tuple(a*s for a,s in zip(settled,(ex,ey,ex,ey)))
        keys = entry_keys(entry_box, entry)
        if keys:
            keys[-1].update(to_json(settled, size))
            result["entryKeys"] = keys
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, help="reuse per-file bounds for unchanged clips")
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()
    if args.cache:
        args.cache.mkdir(parents=True,exist_ok=True)
    folder = RESOURCES / "Animations"
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        measurements = dict(pool.map(measure, ((p, args.cache) for p in sorted(folder.glob("*.apng")))))
    output = {}
    for row in json.loads((RESOURCES / "Spirits.json").read_bytes()):
        key = f"{row['id']:03d}"
        entry = measurements.get(key + "-entry.apng")
        idle = measurements.get(key + "-idle.apng") or measurements.get(key + ".apng")
        if entry or idle:
            output[key] = framing(RESOURCES/"Art"/row["image"],entry,idle)
    path = folder/"framing.json"
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(output, separators=(",", ":"), sort_keys=True) + "\n")
    tmp.replace(path)
    print(f"Framed {len(measurements)} clips across {len(output)} forms.")


if __name__ == "__main__":
    main()
