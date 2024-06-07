#!/usr/bin/env python
import yaml

def find_repositories(data, path=''):
    if isinstance(data, dict):
        if 'repository' in data:
            repository = data['repository']
            image = data.get('image', '')
            version = data.get('version', '')
            print(f"{path},{repository},{image},{version}")
        for key, value in data.items():
            find_repositories(value, path + f"{key}/")
    elif isinstance(data, list):
        for index, item in enumerate(data):
            find_repositories(item, path + f"{index}/")

with open('values.yaml', 'r') as file:
    yaml_data = yaml.safe_load(file)
find_repositories(yaml_data)
