function text(language, english, chinese) {
    return (language === "zh_CN" || language === "auto" && Qt.locale().name.indexOf("zh") === 0) ? chinese : english;
}
function status(language, code) {
    var labels = {
        checking: ["Checking runtime…", "正在检查运行组件…"], needsRuntime: ["Setup required", "需要准备运行组件"], downloading: ["Downloading…", "正在下载…"],
        starting: ["Starting…", "正在启动…"], handshaking: ["Connecting…", "正在连接…"],
        ready: ["Connected", "已连接"], recovering: ["Reconnecting…", "正在重新连接…"],
        failed: ["Backend unavailable · open settings to retry", "后台不可用 · 请打开设置重试"],
        incompatible: ["Update required", "需要更新配套程序"], idle: ["Waiting for a player", "等待播放器"],
        disabled: ["Enable lyrics in settings", "请在设置中开启歌词来源"], unsupported: ["Automatic lyrics unavailable for this content", "当前内容不支持自动搜词"],
        loading: ["Finding lyrics…", "正在查找歌词…"], notFound: ["No lyrics found", "没有找到歌词"],
        ambiguous: ["Choose lyrics in settings", "请在设置中选择歌词"], error: ["Lyrics temporarily unavailable", "歌词暂时不可用"]
    };
    var pair = labels[code] || ["Operation failed: " + code, "操作失败：" + code];
    return text(language, pair[0], pair[1]);
}

function lyricStatus(language, code, errorCode) {
    if (code !== "error" && code !== "notFound") return status(language, code);
    var reasons = {
        invalid_lyrics: ["This lyric version could not be parsed", "这份歌词无法解析，可更换版本"],
        ambiguous_timestamps: ["This lyric version has overlapping timing", "这份歌词时间重叠，可更换版本"],
        no_lyrics: ["No timed lyrics available", "暂无同步歌词"],
        no_synced_lyrics: ["No timed lyrics available", "暂无同步歌词"],
        timeout: ["Lyric request timed out · try again", "歌词请求超时，请重试"],
        rate_limited: ["Lyric source is rate-limiting · try later", "词源请求受限，请稍后重试"],
        provider_error: ["Lyric source is unavailable", "暂时无法取得词源数据"],
        document_too_large: ["Lyric data exceeds the size limit", "歌词数据超出大小限制"],
        storage_error: ["Saved lyrics could not be read", "无法读取已保存的歌词"]
    };
    var pair = reasons[errorCode];
    return pair ? text(language, pair[0], pair[1]) : status(language, code);
}

function runtimeError(language, code) {
    var errors = {
        hash_mismatch: ["Download verification failed. Download the component again.", "下载校验失败，请重新下载运行组件。"],
        size_mismatch: ["The download is incomplete. Try downloading again.", "下载不完整，请重新下载。"],
        unsupported_architecture: ["This build supports Linux x86_64 only.", "此构建仅支持 Linux x86_64。"],
        incompatible_backend: ["The playback component version is incompatible. Install the matching version.", "播放组件版本不兼容，请安装配套版本。"],
        runtime_start_failed: ["The playback component could not start. Check its system dependencies.", "播放组件无法启动，请检查系统依赖。"],
        release_not_available: ["This build has no downloadable playback component.", "此构建尚未提供可下载的播放组件。"],
        storage_error: ["The saved component state could not be read. Your files have been preserved.", "无法读取已保存的组件状态，原文件已保留。"],
        download_failed: ["The download failed. Check your connection and try again.", "下载失败，请检查网络后重试。"],
        unsafe_archive: ["The component archive is invalid. Download a valid package.", "组件归档无效，请下载有效的安装包。"]
    };
    var label = errors[code] || ["The playback component could not be prepared. Retry or reinstall it.", "播放组件准备失败，请重试或重新安装。"];
    return text(language, label[0], label[1]);
}
