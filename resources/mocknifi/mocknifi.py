import base64
import jks
import os
import ssl
import textwrap

from flask import Flask
from tempfile import mkstemp


def to_bytes(s):
    return s.encode('ascii')


def write_pem(f, der_bytes, pem_type):
    f.write(to_bytes("-----BEGIN %s-----\r\n" % pem_type))
    print("-----BEGIN %s-----\r\n" % pem_type, end='')
    f.write(to_bytes("\r\n".join(textwrap.wrap(base64.b64encode(der_bytes).decode('ascii'), 64)) + "\r\n"))
    print("\r\n".join(textwrap.wrap(base64.b64encode(der_bytes).decode('ascii'), 64)), end='')
    f.write(to_bytes("-----END %s-----\r\n" % pem_type))
    print("-----END %s-----\r\n" % pem_type, end='')


def write_private_key(key):
    if not key:
        return

    tf, fn = mkstemp(suffix=".key")
    with os.fdopen(tf, "wb") as f:
        if key.algorithm_oid == jks.util.RSA_ENCRYPTION_OID:
            write_pem(f, key.pkey, "RSA PRIVATE KEY")
        else:
            write_pem(f, key.pkey_pkcs8, "PRIVATE KEY")

        for c in key.cert_chain:
            write_pem(f, c[1], "CERTIFICATE")

    return fn


def write_cert(cert):
    if not cert:
        return

    tf, fn = mkstemp(suffix=".key")
    with os.fdopen(tf, "wb") as f:
        write_pem(f, cert.cert, "CERTIFICATE")

    return fn


def create_ssl_context():
    from os import environ

    # Get the keystore and truststore passwords
    ks_password = environ.get("KEYSTORE_PASSWORD", "")
    ts_password = environ.get("TRUSTSTORE_PASSWORD", "")

    # Get the key and cert details
    key_password = environ.get("TLS_KEY_PASSWORD", "")
    key_id = environ.get("TLS_KEY_ID", "cid")
    cert_id = environ.get("TLS_CERT_ID", "cid")

    # Write the private key
    ks = jks.KeyStore.load("/ssl/keystore.jks", ks_password)
    app_key = write_private_key(ks.private_keys.get(key_id))

    # Write the cert
    ts = jks.KeyStore.load("/ssl/truststore.jks", ts_password)
    app_cert = write_cert(ts.certs.get(cert_id))

    ssl_context = ssl.create_default_context(purpose=ssl.Purpose.CLIENT_AUTH)
    ssl_context.load_cert_chain(certfile=app_cert, keyfile=app_key, password=key_password)
    ssl_context.verify_mode = ssl.CERT_REQUIRED
    return ssl_context


app = Flask("mocknifi")


@app.route('/collection', methods=["POST"])
def post_collection():
    return "YEAH I'M IN"


if __name__ == "__main__":
    app.run(host="0.0.0.0", ssl_context=create_ssl_context())
