// System JXA. Refresh Electron's Mach-O ASAR digest, never disable validation.
ObjC.import("Foundation");
function run(argv) {
    if (argv.length !== 3 || !/^[a-f0-9]{64}$/.test(argv[1]) || !/^[a-f0-9]{64}$/.test(argv[2]))
        throw Error("需要副本框架路径和原/新 ASAR 文件头哈希");
    const handle = $.NSFileHandle.fileHandleForUpdatingAtPath(argv[0]);
    if (!handle) throw Error("副本框架不可写");
    const total = Number(handle.seekToEndOfFile);
    function hex(data) {
        const s=ObjC.unwrap(data.base64EncodedStringWithOptions(0));
        const alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        let result="", bits=0, buffer=0;
        for(const c of s) {
            if(c==="=") break;
            const v=alphabet.indexOf(c); if(v<0) throw Error("Mach-O 数据解码失败");
            buffer=(buffer<<6)|v; bits+=6;
            if(bits>=8) { bits-=8; result+=("0"+((buffer>>>bits)&255).toString(16)).slice(-2); }
        }
        return result;
    }
    function read(offset,size) {
        if (!Number.isSafeInteger(offset) || !Number.isSafeInteger(size) || offset<0 || size<0 || size>1048576 || offset+size>total)
            throw Error("Mach-O 范围异常");
        handle.seekToFileOffset(offset); const data=handle.readDataOfLength(size);
        if (Number(data.length)!==size) throw Error("Mach-O 截断");
        return hex(data);
    }
    function num(h,offset,size,big) {
        const bytes=h.slice(offset*2,(offset+size)*2).match(/../g);
        if (!bytes || bytes.length!==size) throw Error("Mach-O 字段截断");
        const n=parseInt((big?bytes:bytes.reverse()).join(""),16);
        if (!Number.isSafeInteger(n)) throw Error("Mach-O 数值越界");
        return n;
    }
    function ascii(h,offset,size) { return (h.slice(offset*2,(offset+size)*2).match(/../g)||[]).map(b=>String.fromCharCode(parseInt(b,16))).join("").replace(/\0.*$/,""); }
    function digest(header) {
        const data=$.NSString.stringWithString("Resources/app.asarSHA256"+header).dataUsingEncoding($.NSUTF8StringEncoding);
        const task=$.NSTask.alloc.init, input=$.NSPipe.pipe, output=$.NSPipe.pipe;
        task.launchPath="/usr/bin/shasum"; task.arguments=["-a","256"]; task.standardInput=input; task.standardOutput=output;
        task.launch; input.fileHandleForWriting.writeData(data); input.fileHandleForWriting.closeFile;
        const result=ObjC.unwrap($.NSString.alloc.initWithDataEncoding(output.fileHandleForReading.readDataToEndOfFile,$.NSUTF8StringEncoding));
        task.waitUntilExit;
        if (task.terminationStatus!==0 || !/^[a-f0-9]{64}/.test(result)) throw Error("digest 计算失败");
        return result.slice(0,64);
    }
    function bytes(h) { return $.NSData.alloc.initWithBase64EncodedStringOptions(encodeBase64(h),0); }
    function encodeBase64(h) {
        const alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        const b=(h.match(/../g)||[]).map(v=>parseInt(v,16)); let s="";
        for(let i=0;i<b.length;i+=3) { const n=(b[i]<<16)|((b[i+1]||0)<<8)|(b[i+2]||0);
            s+=alphabet[(n>>>18)&63]+alphabet[(n>>>12)&63]+(i+1<b.length?alphabet[(n>>>6)&63]:"=")+(i+2<b.length?alphabet[n&63]:"="); }
        return s;
    }
    try {
        const prefix=read(0,8), magic=num(prefix,0,4,true), slices=[];
        if (magic===0xcafebabe || magic===0xcafebabf) {
            const count=num(prefix,4,4,true), size=magic===0xcafebabf?32:20;
            if (count<1 || count>2) throw Error("不支持的 Universal 架构数量");
            const entries=read(8,count*size);
            for(let i=0;i<count;i++) slices.push(num(entries,i*size+8,size===32?8:4,true));
        } else slices.push(0);
        const positions=[];
        for(const base of slices) {
            const head=read(base,32);
            if (num(head,0,4,false)!==0xfeedfacf) throw Error("不是受支持的 64 位 Mach-O");
            const count=num(head,16,4,false), commandSize=num(head,20,4,false);
            if (count<1 || count>1000 || commandSize>1048576) throw Error("Mach-O 命令异常");
            const commands=read(base+32,commandSize); let at=0, found=0;
            for(let i=0;i<count;i++) {
                const cmd=num(commands,at,4,false), size=num(commands,at+4,4,false);
                if(size<8 || at+size>commandSize) throw Error("Mach-O 命令范围异常");
                if(cmd===0x19) {
                    const sections=num(commands,at+64,4,false);
                    if(72+sections*80>size) throw Error("Mach-O section 异常");
                    for(let j=0;j<sections;j++) {
                        const s=at+72+j*80;
                        if(ascii(commands,s,16)!=="__asar_integrity") continue;
                        const length=num(commands,s+40,8,false), offset=num(commands,s+48,4,false);
                        if(length!==66) throw Error("Electron digest slot 大小变化");
                        const slot=read(base+offset,length);
                        if(ascii(slot,0,32)!=="AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A" || slot.slice(64,68)!=="0101" || slot.slice(68)!==digest(argv[1]))
                            throw Error("内嵌完整性 digest 不匹配或版本不支持");
                        positions.push(base+offset+34); found++;
                    }
                }
                at+=size;
            }
            if(found!==1 || at!==commandSize) throw Error("无法唯一定位每个架构的完整性 digest");
        }
        const data=bytes(digest(argv[2]));
        for(const pos of positions) { handle.seekToFileOffset(pos); handle.writeData(data); }
        handle.synchronizeFile;
        return JSON.stringify({updatedSlices:positions.length,integrityValidationPreserved:true});
    } finally { handle.closeFile; }
}
