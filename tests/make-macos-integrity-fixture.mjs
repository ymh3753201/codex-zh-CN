// Developer-only Mach-O fixtures. No executable program is generated.
import fs from 'node:fs'; import crypto from 'node:crypto';
const [output,mode='arm64']=process.argv.slice(2);
const sha=x=>crypto.createHash('sha256').update(x).digest();
function thin(cpu) {
    const b=Buffer.alloc(250); b.writeUInt32LE(0xfeedfacf); b.writeUInt32LE(cpu,4);
    b.writeUInt32LE(1,16); b.writeUInt32LE(152,20);
    b.writeUInt32LE(0x19,32); b.writeUInt32LE(152,36); b.write('__DATA_CONST',40);
    b.writeUInt32LE(1,96); b.write('__asar_integrity',104); b.write('__DATA_CONST',120);
    b.writeBigUInt64LE(66n,144); b.writeUInt32LE(184,152);
    b.write('AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A',184); b[216]=1; b[217]=1;
    sha('Resources/app.asarSHA256'+'1'.repeat(64)).copy(b,218);
    if(mode==='bad-hash') b[218]^=1;
    if(mode==='bad-version') b[217]=2;
    if(mode==='bad-size') b.writeBigUInt64LE(67n,144);
    return b;
}
let result=thin(mode==='intel'?0x1000007:0x100000c);
if(mode==='universal') {
    result=Buffer.alloc(1024); result.writeUInt32BE(0xcafebabe); result.writeUInt32BE(2,4);
    result.writeUInt32BE(256,16); result.writeUInt32BE(250,20);
    result.writeUInt32BE(512,36); result.writeUInt32BE(250,40);
    thin(0x100000c).copy(result,256); thin(0x1000007).copy(result,512);
}
fs.writeFileSync(output,mode==='truncated'?result.subarray(0,100):result);
