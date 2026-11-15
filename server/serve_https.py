import http.server
import os
import ssl

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "builds", "web")
CERT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "certs", "cert.pem")
KEY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "certs", "key.pem")

os.chdir(ROOT)

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(CERT, KEY)

server = http.server.ThreadingHTTPServer(("0.0.0.0", 8443), http.server.SimpleHTTPRequestHandler)
server.socket = ctx.wrap_socket(server.socket, server_side=True)
print("Serving Majesty on https://0.0.0.0:8443", flush=True)
server.serve_forever()
