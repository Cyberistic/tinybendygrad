import http.server, socketserver, os
os.chdir("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
class H(http.server.SimpleHTTPRequestHandler):
  def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", 8731), H) as httpd:
  httpd.serve_forever()
