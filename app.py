from flask import Flask, jsonify
import datetime
import os
import socket

app = Flask(__name__)

START_TIME = datetime.datetime.utcnow()

@app.route('/')
def home():
    return jsonify({
        "status": "running",
        "message": "Production server is live",
        "timestamp": str(datetime.datetime.utcnow()),
        "hostname": socket.gethostname(),
        "uptime_since": str(START_TIME)
    })

@app.route('/health')
def health():
    return jsonify({
        "status": "healthy",
        "checked_at": str(datetime.datetime.utcnow())
    }), 200

@app.route('/info')
def info():
    return jsonify({
        "python_version": os.popen('python3 --version').read().strip(),
        "platform": os.uname().sysname,
        "container_id": socket.gethostname()
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
