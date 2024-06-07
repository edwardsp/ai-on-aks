#!/bin/bash

helm install volcano oci://$ACR_NAME.azurecr.io/helm/volcano -n volcano-system --create-namespace