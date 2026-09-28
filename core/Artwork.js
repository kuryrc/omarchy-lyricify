// Cover downloads have a separate opt-in from lyric providers.
function source(url, remoteEnabled) {
    if (typeof url !== "string") return "";
    if (url.indexOf("file:///") === 0 || url.indexOf("qrc:/") === 0) return url;
    return remoteEnabled && url.indexOf("https://") === 0 ? url : "";
}
if (typeof module !== "undefined") module.exports = {source: source};
