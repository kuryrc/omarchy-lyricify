// Pure helpers shared by QML and the Node boundary tests. All times are ms.
function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}

function precedingIndex(lines, position) {
    var lo = 0, hi = lines.length - 1, found = -1;
    while (lo <= hi) {
        var mid = (lo + hi) >> 1;
        if (lines[mid].startMs <= position) {
            found = mid;
            lo = mid + 1;
        } else {
            hi = mid - 1;
        }
    }
    return found;
}

function activeIndex(lines, position) {
    var found = precedingIndex(lines, position);
    return found >= 0 && position < lines[found].endMs ? found : -1;
}

function displayIndex(lines, position) {
    var found = precedingIndex(lines, position);
    if (found < 0) return -1;
    if (position < lines[found].endMs) return found;
    // Hold the completed line during short breaths, without advancing its highlight.
    if (found + 1 < lines.length && lines[found + 1].startMs - lines[found].endMs <= 1200)
        return found;
    return -1;
}

function highlightWidth(words, advances, position) {
    if (advances.length !== words.length)
        return 0;
    var edge = 0;
    for (var i = 0; i < words.length; i++) {
        var word = words[i];
        if (position < word.startMs)
            break;
        var start = i === 0 ? 0 : (advances[i - 1] || 0);
        var end = advances[i] || start;
        if (position >= word.endMs) {
            edge = end;
        } else {
            return start + (end - start) * clamp((position - word.startMs) / (word.endMs - word.startMs), 0, 1);
        }
    }
    return edge;
}

function scrollTarget(textWidth, viewportWidth, highlight, elapsed, duration, wordSynced) {
    var overflow = Math.max(0, textWidth - viewportWidth);
    if (!overflow)
        return 0;
    if (wordSynced)
        return clamp(highlight - viewportWidth * 0.58, 0, overflow);
    // A short reading pause at each end; no invented per-word timing.
    return overflow * clamp((elapsed - 900) / Math.max(1, duration - 1800), 0, 1);
}

function approach(current, target, deltaSeconds, response) {
    return current + (target - current) * (1 - Math.exp(-Math.max(0, deltaSeconds) * response));
}

function placement(screenWidth, desiredWidth, offset) {
    var width = clamp(desiredWidth, 240, Math.max(240, screenWidth - 32));
    return {width: width, x: clamp((screenWidth - width) / 2 + offset, 16, Math.max(16, screenWidth - width - 16))};
}

// Hysteresis keeps the center stable until the pointer deliberately leaves it.
function dragPlacement(screenWidth, desiredWidth, candidate, wasSnapped) {
    var snapped = Math.abs(candidate) <= (wasSnapped ? 28 : 16);
    var p = placement(screenWidth, desiredWidth, snapped ? 0 : candidate);
    return {offset: p.x - (screenWidth - p.width) / 2, snapped: snapped};
}

function formatTime(ms) {
    var seconds = Math.floor(Math.max(0, ms) / 1000);
    return Math.floor(seconds / 60) + ":" + (seconds % 60 < 10 ? "0" : "") + seconds % 60;
}

function validate(track) {
    if (!track || track.schemaVersion !== 1 || !Array.isArray(track.lines)
            || !Number.isFinite(track.durationMs) || track.durationMs <= 0)
        return false;
    var previousEnd = 0;
    for (var i = 0; i < track.lines.length; i++) {
        var line = track.lines[i];
        if (typeof line.text !== "string" || !Number.isFinite(line.startMs) || !Number.isFinite(line.endMs)
                || line.startMs < previousEnd || line.endMs <= line.startMs || line.endMs > track.durationMs)
            return false;
        previousEnd = line.endMs;
        var words = line.words || [], text = "", previousWordEnd = line.startMs;
        if (!Array.isArray(words))
            return false;
        for (var j = 0; j < words.length; j++) {
            var word = words[j];
            if (typeof word.text !== "string" || !Number.isFinite(word.startMs) || !Number.isFinite(word.endMs)
                    || word.startMs < previousWordEnd || word.endMs <= word.startMs || word.endMs > line.endMs)
                return false;
            previousWordEnd = word.endMs;
            text += word.text;
        }
        if (words.length && text !== line.text)
            return false;
    }
    return true;
}

function newStats() {
    return {count: 0, totalMs: 0, maxMs: 0, slow: 0, warmup: 8, bins: {}};
}

function sample(stats, ms, refreshRate) {
    if (stats.warmup > 0) { stats.warmup--; return; }
    if (!Number.isFinite(ms) || ms <= 0) return;
    var bucket = Math.min(10000, Math.round(ms * 10));
    stats.bins[bucket] = (stats.bins[bucket] || 0) + 1;
    stats.count++;
    stats.totalMs += ms;
    stats.maxMs = Math.max(stats.maxMs, ms);
    if (ms > 1500 / refreshRate) stats.slow++;
}

function statsReport(stats) {
    function percentile(p) {
        var keys = Object.keys(stats.bins).map(Number).sort(function(a, b) { return a - b; });
        var target = Math.ceil(stats.count * p), count = 0;
        for (var i = 0; i < keys.length; i++) {
            count += stats.bins[keys[i]];
            if (count >= target) return keys[i] / 10;
        }
        return 0;
    }
    return {kind: "qt-animation-callback", samples: stats.count, seconds: stats.totalMs / 1000,
        p50Ms: percentile(0.5), p95Ms: percentile(0.95), p99Ms: percentile(0.99),
        maxMs: stats.maxMs, overBudget: stats.slow};
}
