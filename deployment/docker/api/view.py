from flask import Flask, flash, redirect, render_template, jsonify, request
import os
import main
import re
import glob
import yaml
from jsonschema import validate, ValidationError

app = Flask(__name__)
app.config['JSON_SORT_KEYS'] = False

### Common Endpoints ###

@app.route('/api/v1/version', methods=['GET'])
def version():
    resp, code = main.enabler_version()
    return jsonify(resp), code

@app.route('/api/v1/health', methods=['GET'])
def health():
    resp, code = main.enabler_health()
    return jsonify(resp),code

@app.route('/api/v1/api-export', methods=['GET'])
def apiexport():
    resp, code = main.enabler_apiexport()
    return jsonify(resp), code

### API ###

types = {
    'firewall': ['zones','snats','dnats','forwardings','rules'],
    'mwan3': ['policies','rules']
}

@app.route('/api/v1/<string:type>/<string:endpoint>', defaults={'name': None}, methods=['GET'])
@app.route('/api/v1/<string:type>/<string:endpoint>/<string:name>', methods=['GET'])
def GET(type,endpoint,name):
    if not (type in types and endpoint in types[type]): 
        return jsonify({'message':'Invalid endpoint'}),404
    resp, code = main.GET(type,endpoint,name)
    return jsonify(resp),code

@app.route('/api/v1/<string:type>/<string:endpoint>', methods=['POST'])
def POST(type,endpoint):
    if not (type in types and endpoint in types[type]): 
        return jsonify({'message':'Invalid endpoint'}),404
    content_type = request.headers.get('Content-Type')
    if not(content_type == 'application/json'): 
        return jsonify({'message': 'Content-Type not supported!'}), 406
    resp, code = main.POST(type,endpoint,request.json)
    return jsonify(resp), code

@app.route('/api/v1/<string:type>/<string:endpoint>/<string:name>', methods=['DELETE'])
def DELETE(type,endpoint,name):
    if not (type in types and endpoint in types[type]): 
        return jsonify({'message':'Invalid endpoint'}),404
    resp, code = main.DELETE(type,endpoint,name)
    return jsonify(resp), code

### MAIN ###

if __name__ == "__main__":
    port = int(os.environ.get('API_PORT'))
    app.run(debug=True, host='0.0.0.0', port=port)