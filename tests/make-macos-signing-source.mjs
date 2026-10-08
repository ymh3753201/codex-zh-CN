// Developer-only: real linker section, no Codex code or private data.
import fs from 'node:fs';
import crypto from 'node:crypto';
const [asar, output] = process.argv.slice(2);
const data = fs.readFileSync(asar);
const header = crypto.createHash('sha256').update(data.subarray(16, 16 + data.readUInt32LE(12))).digest('hex');
const digest = crypto.createHash('sha256').update('Resources/app.asarSHA256' + header).digest();
const slot = Buffer.concat([Buffer.from('AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A'), Buffer.from([1, 1]), digest]);
fs.writeFileSync(output, `__attribute__((used,section("__DATA_CONST,__asar_integrity")))\nconst unsigned char codex_test_digest[66] = {${[...slot].join(',')}};\nint main(void) { return 0; }\n`);
console.log(header);
