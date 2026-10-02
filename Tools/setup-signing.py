#!/usr/bin/env python3
"""Prepare a private, app-specific signing identity; never install a trusted root."""
import os, secrets, subprocess, sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
folder = root / '.signing'
folder.mkdir(mode=0o700, exist_ok=True)
os.chmod(folder, 0o700)
os.umask(0o077)
password_file = folder / 'keychain-password'
if not password_file.exists(): password_file.write_text(secrets.token_urlsafe(32))
password = password_file.read_text().strip()
config = folder / 'certificate.conf'
config.write_text('''[req]
prompt=no
distinguished_name=dn
x509_extensions=code_signing
[dn]
CN=Lanes Local Development
[code_signing]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
''')
def run(step, args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode:
        print('Signing setup failed at ' + step, file=sys.stderr)
        # Never include invocation arguments, passwords, or private key data.
        print(result.stderr[:2000], file=sys.stderr)
        sys.exit(result.returncode)
    return result.stdout
cert, key, p12 = folder/'certificate.pem', folder/'private-key.pem', folder/'identity.p12'
if not cert.exists():
    run('certificate generation', ['/usr/bin/openssl','req','-x509','-newkey','rsa:2048','-nodes','-sha256','-days','3650','-config',str(config),'-keyout',str(key),'-out',str(cert)])
if not p12.exists():
    run('identity preparation', ['/usr/bin/openssl','pkcs12','-export','-in',str(cert),'-inkey',str(key),'-out',str(p12),'-name','Lanes Local Development','-passout','file:'+str(password_file)])
if '--import' not in sys.argv:
    print('Prepared Lanes Local Development certificate and private identity in .signing (owner-only access).')
    sys.exit(0)
keychain = folder/'lanes-signing.keychain-db'
if not keychain.exists(): run('dedicated keychain creation', ['/usr/bin/security','create-keychain','-p',password,str(keychain)])
run('dedicated keychain unlock', ['/usr/bin/security','unlock-keychain','-p',password,str(keychain)])
marker = folder/'imported'
if not marker.exists():
    run('private identity import', ['/usr/bin/security','import',str(p12),'-k',str(keychain),'-P',password,'-T','/usr/bin/codesign'])
    run('codesign key access', ['/usr/bin/security','set-key-partition-list','-S','apple-tool:,apple:,codesign:','-s','-k',password,str(keychain)])
    marker.write_text('Lanes Local Development\n')
print('Lanes local signing identity ready in a dedicated keychain. No root trust or window permissions changed.')
