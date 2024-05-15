from kubernetes import client, config
from kubernetes.client.rest import ApiException
from peewee import *
import os
import json
import requests
from datetime import datetime, timedelta
import json
import yaml

api_port = os.environ['API_PORT']
namespace = os.environ['namespace']
sdewanPurpose = os.environ['sdewanPurpose']
group = os.environ['group']
version = os.environ['version']

def enabler_version():
    headers = ['enabler','version']
    data = [os.environ['ENABLER_NAME'],os.environ['ENABLER_VERSION']]
    return dict(zip(headers,data)),200

def enabler_health():
    health_status = True
    if health_status:
        return {'status': 'healthy'},200
    else:
        return {'status': 'unhealthy'},503

def enabler_apiexport():
    f = open('openapi.yaml')
    data = yaml.load(f, Loader=yaml.Loader)
    return data,200

def k8s_client():
    config.load_incluster_config()
    return client.CustomObjectsApi()

def list_object(plural):
    return k8s_client().list_namespaced_custom_object(group, version, namespace, plural)

def get_kind(name):
    resources = k8s_client().get_api_resources(group,version).to_dict()
    for resource in resources['resources']:
        if resource['name'] == name:
            return resource['kind']
    return 'None'

def create_object(plural,data,body):
    try:
        k8s_client().create_namespaced_custom_object(group, version, namespace, plural, body)
        return data,201
    except ApiException as e:
        if e.status == 409:
            return {'message': 'Object already exists'},e.status
        else:
            return {'message': 'Error creating object'},e.status
        
def delete_object(plural,name):
    try:
        k8s_client().delete_namespaced_custom_object(group,version,namespace,plural,name)
        return {'message': 'Object deleted successfully'},200
    except ApiException as e:
        if e.status == 404:
            return {'message': 'Object not found'},e.status
        else:
            return {'message': 'Error deleting object'},e.status
        
def GET(type,endpoint,name):
    plural = str(type + endpoint)
    object = list_object(plural)
    if not object['items']:
        if not name:
            return {'message': 'No '+type+' '+endpoint+' found'},404
        else:
            return {'message': ''+type+' '+endpoint+' not found for the given name'},404
    data = []
    for item in object['items']:
        keys = item['spec'].keys()
        obj = {'metadata': {'name': item['metadata']['name']}, 'spec': {}}
        for key in keys:
            obj['spec'][key] = item['spec'][key]
        data.append(obj) 
    if not name: return data,200
    for obj in data:
        if obj['metadata']['name'] == name: return obj,200
    return {'message': ''+type+' '+endpoint+' not found for the given name'},404

def POST(type,endpoint,data):
    plural = str(type + endpoint)
    data = json.loads(json.dumps(data))
    body = {
    "apiVersion": group+"/"+version,
    "kind": get_kind(plural),
    "metadata": {
      "name": data['metadata']['name'],
      "namespace": namespace,
      "labels": {
         "sdewanPurpose": sdewanPurpose
      }
    },
    "spec": data['spec']
    }
    body = json.loads(json.dumps(body))
    return create_object(plural,data,body)

def DELETE(type,endpoint,name):
    plural = str(type + endpoint)
    return delete_object(plural,name)
