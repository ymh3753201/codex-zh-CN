"""Exercise the actual installed renderer, with the remote i18n switch disabled.

No app launch or user config changes. Python/Node are developer dependencies only.
"""
import hashlib
import json
import os
import pathlib
import re
import shutil
import struct
import subprocess
import tempfile
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def read_asar(path):
    with path.open('rb') as stream:
        prefix = stream.read(16)
        base = 8 + struct.unpack_from('<I', prefix, 4)[0]
        header = json.loads(stream.read(struct.unpack_from('<I', prefix, 12)[0]))
    return base, header


def entry_bytes(path, base, entry):
    with path.open('rb') as stream:
        stream.seek(base + int(entry['offset']))
        result = stream.read(entry['size'])
    assert len(result) == entry['size']
    return result


def renderer_check(content, expect_chinese):
    # Run the production React component with controlled hooks, rather than
    # duplicating its gating condition in the test.
    marker = content.index('localeOverride:r}=e')
    start = content.rfind('function ', 0, marker)
    end = content.index('function ', marker)
    component = content[start:end]
    name = re.match(r'function ([\w$]+)', component)[1]
    # Minified names change on every Codex release. Derive each binding's role
    # from the component's structure; fail loudly if a role cannot be found.
    def role(pattern, label):
        found = re.search(pattern, component)
        if not found:
            raise AssertionError(f'Renderer structure changed ({label}); review before patching: {name}')
        return found[1]
    override = role(r'localeOverride:([\w$]+)\}=e', 'localeOverride prop')
    roles = {
        'cache': role(r'\(0,([\w$]+)\.c\)', 'memo cache'),
        'react': role(r'\(0,([\w$]+)\.useState\)', 'react'),
        'jsx': role(r'\(0,([\w$]+)\.jsx\)', 'jsx runtime'),
        'flag': role(r'([\w$]+)\(`\d{4,}`\)', 'feature layer hook'),
        'data': role(r'\{data:[\w$]+\}=([\w$]+)\(', 'locale data hook'),
        'isDefault': role(r'[\w$]+=([\w$]+)\(' + re.escape(override) + r'\)', 'default-locale check'),
        'resolve': role(r'try\{let e;[^;{}]*?e=([\w$]+)\(', 'locale resolver'),
        'load': role(r'await ([\w$]+)\(', 'message loader'),
    }
    js = f'''
const assert = require('node:assert/strict');
let current = null, effects = [];
const stub = new Proxy(function(x){{ return x; }}, {{ get: (t, k) => k === Symbol.toPrimitive ? undefined : stub }});
const roles = {{
  {roles['cache']}: {{c: n => Array(n).fill(Symbol('empty'))}},
  {roles['react']}: {{useState: () => [current, v => current = v], useEffect: f => effects.push(f)}},
  {roles['jsx']}: {{jsx: (type, props) => props}},
  {roles['flag']}: () => ({{get: (key, fallback) => key === 'enable_i18n' ? false : fallback}}),
  {roles['data']}: () => ({{data: {{ideLocale: 'en-US', systemLocale: 'en-US'}}}}),
  {roles['isDefault']}: x => !x || x === 'en-US',
  {roles['resolve']}: x => ({{locale: x}}),
  {roles['load']}: async () => ({{greeting: '你好'}}),
  document: {{documentElement: {{}}}},
}};
const scope = new Proxy(roles, {{
  has: (t, k) => typeof k === 'string' && k !== 'component' && (k in t || !(k in globalThis)),
  get: (t, k) => k === Symbol.unscopables ? undefined : (k in t ? t[k] : stub),
}});
const component = (function() {{ with (scope) {{ return (function() {{ {component}; return {name}; }})(); }} }})();
(async()=>{{
  let result=component({{localeOverride:'zh-CN',children:'test'}});
  effects.forEach(f=>f()); await new Promise(resolve=>setImmediate(resolve));
  result=component({{localeOverride:'zh-CN',children:'test'}});
  assert.equal(result.locale,'zh-CN');
  assert.equal(result.messages?.greeting==='你好', {str(expect_chinese).lower()});
  console.log('PASS: production renderer ({name}), remote switch false, Chinese loaded =', {str(expect_chinese).lower()});
}})().catch(e=>{{console.error(e);process.exitCode=1}});
'''
    # Run as a sloppy-mode CommonJS file: the harness relies on `with` to
    # supply every free minified binding the component references.
    with tempfile.NamedTemporaryFile('w', suffix='.cjs', delete=False, encoding='utf-8') as script:
        script.write(js)
    try:
        subprocess.run(['node', script.name], check=True)
    finally:
        os.unlink(script.name)


def main():
    path = pathlib.Path(sys.argv[1])
    original_hash = hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()
    base, header = read_asar(path)
    assets = header['files']['webview']['files']['assets']['files']
    name = next(n for n in assets if n.startswith('app-initial-') and b'enable_i18n' in entry_bytes(path, base, assets[n]))
    original = entry_bytes(path, base, assets[name]).decode()
    renderer_check(original, False)
    with tempfile.TemporaryDirectory(prefix='codex-zh-gate-') as folder:
        app = pathlib.Path(folder)
        (app / 'resources').mkdir()
        dest = app / 'resources/app.asar'
        shutil.copyfile(path, dest)
        exe = app / 'ChatGPT.exe'
        # Exercise the classic Electron embedded integrity marker as well.
        raw_header = json.dumps(header, separators=(',', ':'), ensure_ascii=False)
        with path.open('rb') as f:
            f.seek(12); length = struct.unpack('<I', f.read(4))[0]; raw = f.read(length)
        old_hash = hashlib.sha256(raw).hexdigest()
        exe.write_bytes(b'MZ' + ('{"file":"resources\\\\app.asar","alg":"SHA256","value":"' + old_hash + '"}').encode())
        command = "$ErrorActionPreference='Stop'; . '" + str(ROOT / 'scripts/locale-compat.ps1').replace("'", "''") + "'; Set-LocaleCompatibility '" + str(app).replace("'", "''") + "'"
        subprocess.run([os.environ.get('CODEX_ZH_PWSH', 'powershell.exe'), '-NoProfile', '-Command', command], check=True)
        new_base, new_header = read_asar(dest)
        new_assets = new_header['files']['webview']['files']['assets']['files']
        patched = entry_bytes(dest, new_base, new_assets[name]).decode()
        renderer_check(patched, True)
        assert new_base == base
        changed = []
        for asset, entry in assets.items():
            if entry.get('unpacked') or 'offset' not in entry:
                continue
            after = new_assets[asset]
            data = entry_bytes(dest, new_base, after)
            if after != entry:
                changed.append(asset)
                assert len(data) == entry['size']
                assert hashlib.sha256(data).hexdigest() == after['integrity']['hash']
                block_size = after['integrity']['blockSize']
                assert [hashlib.sha256(data[i:i+block_size]).hexdigest() for i in range(0, len(data), block_size)] == after['integrity']['blocks']
            else:
                assert data == entry_bytes(path, base, entry), asset
        assert len(changed) == 2, changed
        with dest.open('rb') as f:
            f.seek(12); length = struct.unpack('<I', f.read(4))[0]; new_hash = hashlib.sha256(f.read(length)).hexdigest()
        assert new_hash.encode() in exe.read_bytes()
        print('PASS: fixed-length resources, block hashes, executable header hash, unchanged unrelated assets')
    assert hashlib.file_digest(path.open('rb'), 'sha256').hexdigest() == original_hash
    print('PASS: official installation untouched')


if __name__ == '__main__':
    main()
