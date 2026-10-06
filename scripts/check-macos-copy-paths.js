// Read-only physical-path audit before any copied bundle write or signing.
ObjC.import("Foundation");
function run(argv) {
    if (argv.length !== 1) throw Error("需要受管副本根");
    function physical(p) { return ObjC.unwrap($.NSString.stringWithString(p).stringByStandardizingPath.stringByResolvingSymlinksInPath); }
    const root = physical(argv[0]), fm = $.NSFileManager.defaultManager;
    if (!/\/copies\/copy\.[^/]+\/Codex中文版\.app$/.test(root)) throw Error("不是受管副本根");
    const enumeration = fm.enumeratorAtPath(root);
    if (!enumeration) throw Error("无法遍历副本");
    let entry;
    while ((entry = enumeration.nextObject)) {
        const p = physical(root + "/" + ObjC.unwrap(entry));
        if (p.indexOf(root + "/") !== 0) throw Error("副本包含越界链接，未修改文件");
        const attrs = fm.attributesOfItemAtPathError(p, null);
        if (!attrs) throw Error("副本包含损坏链接或缺失目标");
        const type = ObjC.unwrap(attrs.objectForKey($.NSFileType));
        if (type === "NSFileTypeRegular" && Number(ObjC.unwrap(attrs.objectForKey($.NSFileReferenceCount))) !== 1)
            throw Error("副本包含共享硬链接，未修改文件");
    }
    return JSON.stringify({physicalPathsConfined:true});
}
