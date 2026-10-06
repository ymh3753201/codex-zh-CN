// macOS system JavaScript for Automation. Never execute ASAR code.
// Read-only by default; patch mode is limited to an independently verified copy.
ObjC.import("Foundation");

function text(data) {
    const value = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
    if (!value) throw Error("资源不是有效 UTF-8");
    return ObjC.unwrap(value);
}

function sha256(data) {
    const task = $.NSTask.alloc.init;
    task.launchPath = "/usr/bin/shasum";
    task.arguments = ["-a", "256"];
    const input = $.NSPipe.pipe, output = $.NSPipe.pipe;
    task.standardInput = input;
    task.standardOutput = output;
    task.launch;
    input.fileHandleForWriting.writeData(data);
    input.fileHandleForWriting.closeFile;
    const result = text(output.fileHandleForReading.readDataToEndOfFile);
    task.waitUntilExit;
    if (task.terminationStatus !== 0 || !/^[a-f0-9]{64}/.test(result)) throw Error("SHA-256 校验失败");
    return result.slice(0, 64);
}

function run(argv) {
    const patch = argv.length === 3 && argv[1] === "--patch-copy";
    if (argv.length !== 1 && !patch) throw Error("需要一个 app.asar 路径");
    if (patch && (argv[0] === argv[2] ||
        ObjC.unwrap($.NSString.stringWithString(argv[0]).stringByResolvingSymlinksInPath) ===
        ObjC.unwrap($.NSString.stringWithString(argv[2]).stringByResolvingSymlinksInPath)))
        throw Error("禁止修改官方 ASAR");
    const handle = $.NSFileHandle.fileHandleForReadingAtPath(argv[0]);
    if (!handle) throw Error("无法读取 app.asar");
    const fileSize = Number(handle.seekToEndOfFile);
    function read(offset, size) {
        if (!Number.isSafeInteger(offset) || !Number.isSafeInteger(size) || offset < 0 || size < 0 ||
            size > 67108864 || offset + size > fileSize) throw Error("ASAR 资源范围越界或截断");
        handle.seekToFileOffset(offset);
        const data = handle.readDataOfLength(size);
        if (Number(data.length) !== size) throw Error("ASAR 资源截断");
        return data;
    }
    try {
        const description = ObjC.unwrap(read(0, 16).description);
        const hex = description.indexOf("0x") >= 0 ? description.match(/0x([a-f0-9]+)/i)[1] : description.replace(/[<>\s]/g, "");
        function u32(offset) {
            const bytes = hex.slice(offset * 2, offset * 2 + 8).match(/../g);
            return parseInt(bytes.reverse().join(""), 16);
        }
        const headerSize = u32(4), jsonSize = u32(12), base = 8 + headerSize;
        if (u32(0) !== 4 || jsonSize < 2 || headerSize < jsonSize + 8 || headerSize > 67108864 || base > fileSize)
            throw Error("ASAR 文件头异常");
        const header = read(16, jsonSize);
        const originalHeader = text(header), tree = JSON.parse(originalHeader);
        const writes = [];
        function entry(path) {
            let node = tree;
            for (const part of path.split("/")) node = node && node.files && node.files[part];
            return node;
        }
        function verified(path) {
            const node = entry(path);
            if (!node || node.unpacked || node.link || !/^\d+$/.test(String(node.offset))) throw Error("资源缺失或结构不支持：" + path);
            const data = read(base + Number(node.offset), node.size);
            const integrity = node.integrity;
            if (!integrity || integrity.algorithm !== "SHA256" || !/^[a-f0-9]{64}$/.test(integrity.hash) ||
                !Number.isSafeInteger(integrity.blockSize) || integrity.blockSize <= 0 || !Array.isArray(integrity.blocks) ||
                integrity.blocks.length !== Math.ceil(node.size / integrity.blockSize)) throw Error("资源完整性记录异常：" + path);
            if (sha256(data) !== integrity.hash) throw Error("资源 SHA-256 不一致：" + path);
            for (let offset = 0, index = 0; offset < node.size; offset += integrity.blockSize, index++) {
                const length = Math.min(integrity.blockSize, node.size - offset);
                if (sha256(data.subdataWithRange($.NSMakeRange(offset, length))) !== integrity.blocks[index])
                    throw Error("资源分块 SHA-256 不一致：" + path);
            }
            return text(data);
        }
        const nativeText = verified("native-menu-locales/zh-CN.json");
        const nativeMessages = JSON.parse(nativeText);
        if (!nativeMessages || typeof nativeMessages !== "object" || !/[\u3400-\u9fff]/.test(nativeText))
            throw Error("菜单中文词条无效");
        const assetNode = entry("webview/assets");
        if (!assetNode || !assetNode.files) throw Error("缺少主界面资源目录");
        const names = Object.keys(assetNode.files);
        const chinese = names.filter(function (n) { return /^zh-CN-[^/]+\.js$/.test(n); });
        if (chinese.length !== 1 || !/[\u3400-\u9fff]/.test(verified("webview/assets/" + chinese[0])))
            throw Error("主界面中文词条缺失或不唯一");
        const build = entry(".vite/build");
        const mainNames = build && build.files ? Object.keys(build.files).filter(function (n) { return /^main-[^/]+\.js$/.test(n); }) : [];
        if (mainNames.length !== 1) throw Error("无法唯一定位主进程语言逻辑");
        const mainText = verified(".vite/build/" + mainNames[0]);
        if (mainText.indexOf("localeOverride") < 0 || mainText.indexOf("nativeIntl") < 0) throw Error("主进程不支持预期语言设置");
        const candidates = names.filter(function (n) { return /^(app-initial|index|general-settings)-[^/]+\.js$/.test(n); });
        const evidence = [], renderers = [];
        let uncertain = false;
        for (const name of candidates) {
            const source = verified("webview/assets/" + name);
            if (/^(app-initial|index)-/.test(name) && source.indexOf("localeOverride") >= 0) renderers.push(name);
            if (source.indexOf("true/*zh-cn*/") >= 0) {
                if ((source.match(/true\/\*zh-cn\*\//g) || []).length !== 1 || source.indexOf("enable_i18n") >= 0)
                    throw Error("副本翻译补丁标记异常");
                evidence.push({asset: name, supportedPattern: true, locallyForced: true});
                continue;
            }
            if (source.indexOf("enable_i18n") < 0) continue;
            // Keep the false/true fallback separate from the account's real remote value.
            const gates = source.match(/[A-Za-z_$][\w$]*(?:\(`\d{4,}`\))?\?\.get\(`enable_i18n`,![01]\)/g) || [];
            const unique = gates.length === 1 && (source.match(/enable_i18n/g) || []).length === 1;
            if (!unique || source.indexOf("localeOverride") < 0) uncertain = true;
            const finding = { asset: name, supportedPattern: unique };
            if (unique) finding.defaultEnabled = /,!0\)$/.test(gates[0]);
            evidence.push(finding);
            if (patch && unique && source.indexOf("localeOverride") >= 0) {
                const marker = "true/*zh-cn*/";
                const replacement = marker + " ".repeat(gates[0].length - marker.length);
                const changed = source.replace(gates[0], replacement);
                const data = $.NSString.stringWithString(changed).dataUsingEncoding($.NSUTF8StringEncoding);
                const node = entry("webview/assets/" + name);
                if (Number(data.length) !== node.size) throw Error("补丁长度变化，已停止");
                writes.push({node: node, data: data});
            }
        }
        if (renderers.length !== 1 || evidence.some(function (e) { return !e.supportedPattern; })) uncertain = true;
        const gateDetected = evidence.some(function (e) { return /^(app-initial|index)-/.test(e.asset); });
        if (evidence.length && !gateDetected) uncertain = true;
        if (patch) {
            if (uncertain || !gateDetected || writes.length !== evidence.length || writes.length < 1 || writes.length > 2)
                throw Error("翻译逻辑不受支持，禁止猜测修改");
            if (JSON.stringify(tree) !== originalHeader) throw Error("ASAR 文件头格式变化，禁止重排资源");
            for (const change of writes) {
                const integrity = change.node.integrity;
                integrity.hash = sha256(change.data);
                integrity.blocks = [];
                for (let offset = 0; offset < change.node.size; offset += integrity.blockSize)
                    integrity.blocks.push(sha256(change.data.subdataWithRange($.NSMakeRange(offset,
                        Math.min(integrity.blockSize, change.node.size - offset)))));
            }
            const changedHeader = $.NSString.stringWithString(JSON.stringify(tree)).dataUsingEncoding($.NSUTF8StringEncoding);
            if (Number(changedHeader.length) !== jsonSize) throw Error("ASAR 完整性记录长度变化");
            const writer = $.NSFileHandle.fileHandleForUpdatingAtPath(argv[0]);
            if (!writer) throw Error("副本不可写");
            try {
                for (const change of writes) {
                    writer.seekToFileOffset(base + Number(change.node.offset));
                    writer.writeData(change.data);
                }
                writer.seekToFileOffset(16); writer.writeData(changedHeader); writer.synchronizeFile;
            } finally { writer.closeFile; }
            return JSON.stringify({patchedAssets: evidence.map(function(e) { return e.asset; }),
                headerSha256: sha256(changedHeader)});
        }
        return JSON.stringify({ resourcesReady: true, headerSha256: sha256(header), languageGateDetected: gateDetected,
            languageGateStatus: uncertain ? "unrecognized" : evidence.some(function(e) { return e.locallyForced; }) ?
                "local-copy-enabled" : gateDetected ? "remote-dependent" : "not-detected",
            remoteLanguageGateValue: "unknown", gateEvidence: evidence, rendererAsset: renderers[0] || "" });
    } finally { handle.closeFile; }
}
