#!/bin/bash

#-------------------------------------------
# Global Variables and Configurations
#-------------------------------------------
GENERIC_FAULT_CODE="NHC2001"
GENERIC_FAULT_CODE_VALUE="Resource.Hpc.Unhealthy.HpcGenericFailure"

# Variables set via command-line options
file_path=""
impact_rp_trigger=""

#-------------------------------------------
# Inline Fault Code Mappings (Error Codes)
#-------------------------------------------
declare -A NHC_ERROR_CODES=(
    ["NHC2001"]="Resource.Hpc.Unhealthy.HpcGenericFailure"        # Generic failure
    ["NHC2002"]="Resource.Hpc.Unhealthy.MissingIB"                 # Missing InfiniBand
    ["NHC2003"]="Resource.Hpc.Unhealthy.IBPerformance"           # Degraded IB performance
    ["NHC2004"]="Resource.Hpc.Unhealthy.IBPortDown"              # IB port persistently down
    ["NHC2005"]="Resource.Hpc.Unhealthy.IBPortFlapping"          # IB port flapping
    ["NHC2007"]="Resource.Hpc.Unhealthy.HpcRowRemapFailure"      # GPU row remap failure
    ["NHC2008"]="Resource.Hpc.Unhealthy.HpcInforomCorruption"      # GPU infoROM corruption
    ["NHC2009"]="Resource.Hpc.Unhealthy.HpcMissingGpu"           # Missing GPUs
    ["NHC2010"]="Resource.Hpc.Unhealthy.ManualInvestigation"     # Requires manual investigation
    ["NHC2011"]="Resource.Hpc.Unhealthy.XID95UncontainedECCError"  # NVRM Xid 95 error
    ["NHC2012"]="Resource.Hpc.Unhealthy.XID94ContainedECCError"    # NVRM Xid 94 error
    ["NHC2013"]="Resource.Hpc.Unhealthy.XID79FallenOffBus"         # NVRM Xid 79 error
    ["NHC2014"]="Resource.Hpc.Unhealthy.XID48DoubleBitECC"         # NVRM Xid 48 error
    ["NHC2015"]="Resource.Hpc.Unhealthy.UnhealthyGPUNvidiasmi"       # Nvidia-smi hang
    ["NHC2016"]="Resource.Hpc.Unhealthy.NvLink"                    # NvLink down
    ["NHC2017"]="Resource.Hpc.Unhealthy.HpcDcgmiThermalReport"     # Thermal violations from DCGMI
    ["NHC2018"]="Resource.Hpc.Unhealthy.ECCPageRetirementTableFull" # ECC error page retirements threshold
    ["NHC2019"]="Resource.Hpc.Unhealthy.DBEOverLimit"              # More than 10 DBE retired pages in a week
    ["NHC2020"]="Resource.Hpc.Unhealthy.HpcGpuDcgmDiagFailure"     # GPU DCGMI diagnostic failure
    ["NHC2021"]="Resource.Hpc.Unhealthy.GPUMemoryBWFailure"        # GPU memory bandwidth issue
    ["NHC2022"]="Resource.Hpc.Unhealthy.CPUPerformance"            # CPU performance issue
)

#-------------------------------------------
# Usage Information
#-------------------------------------------
usage() {
    echo -e "\e[94mUsage: $0 [-f <file_path>]\e[0m"
    echo ""
    echo "Options:"
    echo "  -f <file_path>   Trigger Impact Reporting using the provided health log file path."
    exit 1
}

#-------------------------------------------
# Parse Command-Line Arguments
#-------------------------------------------
parse_args() {
    while getopts "f:" opt; do
        case $opt in
            f)
                file_path="$OPTARG"
                impact_rp_trigger="true"
                ;;
            *)
                echo -e "\e[91mOption not recognised.\e[0m"
                usage
                ;;
        esac
    done

    if [[ -z "$file_path" ]]; then
        echo -e "\e[91mNo valid options provided.\e[0m"
        usage
    fi
}

#-------------------------------------------
# Use File to Trigger Impact Reporting
#-------------------------------------------
use_file_trigger() {
    if [ ! -f "$file_path" ]; then
        echo -e "\e[91mFile '$file_path' does not exist.\e[0m"
        exit 1
    fi
    failure_report_file=$(realpath "$file_path")
    echo "Using failure report file: $failure_report_file"
}

#-------------------------------------------
# Determine Fault Code from Log or User Input
#-------------------------------------------
get_fault_code() {
    if [ -n "${failure_report_file:-}" ]; then
        fault_code=$(grep -o "FaultCode: NHC[0-9]\+" "$failure_report_file" | awk -F': ' '{print $2}' | head -n 1)
        if [ -z "$fault_code" ]; then
            echo -e "\e[91mFault code not found in log file.\e[0m"
            exit 1
        fi
        export nhc_error=$(grep -m 1 "FaultCode: $fault_code" "$failure_report_file")
        echo "Detected fault code: $fault_code"
        echo "NHC error: $nhc_error"
    else
        fault_code="$user_defined_fault_code"
        echo "User defined fault code: $fault_code"
    fi
}

#-------------------------------------------
# Get Fault Code Value and Impact Category
#-------------------------------------------
get_fault_code_value() {
    if [[ -v NHC_ERROR_CODES["$fault_code"] ]]; then
        fault_code_value="${NHC_ERROR_CODES[$fault_code]}"
    else
        fault_code_value="$GENERIC_FAULT_CODE_VALUE"
    fi
    impact_category="$fault_code_value"
    echo "Impact category set to: $impact_category"
}

#-------------------------------------------
# Get Impact Description
#-------------------------------------------
get_impact_description() {
    impact_description=$(echo "$nhc_error" | cut -d':' -f5- | sed 's/^ //')
    if [ -z "$impact_description" ]; then
        impact_description="$fault_code"
    fi
    echo "Impact description: $impact_description"
}

#-------------------------------------------
# Get Physical Hostnames
#-------------------------------------------
get_physical_hostname() {
    physical_hostname=$(tr -d '\0' < /var/lib/hyperv/.kvp_pool_3 | sed -e 's/.*Qualified\(.*\)VirtualMachineDynamic.*/\1/')
    echo "Physical hostname: $physical_hostname"
}

#-------------------------------------------
# Retrieve OAuth2 Token and Instance Metadata
#-------------------------------------------
retrieve_metadata() {
    local oauth2_token_url oauth2_token_common_url
    oauth2_token_common_url="http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F"
    if [ -z "${OBJECT_ID:-}" ]; then
        oauth2_token_url="$oauth2_token_common_url"
    else
        oauth2_token_url="$oauth2_token_common_url&object_id=$OBJECT_ID"
    fi
    oauth2_token=$(curl -s -H Metadata:true "$oauth2_token_url")
    access_token=$(echo "$oauth2_token" | jq -r '.access_token')

    subscriptionId=$(curl -s -H Metadata:true --max-time 10 "http://169.254.169.254/metadata/instance/compute/subscriptionId?api-version=2021-01-01&format=text")
    resourceId=$(curl -s -H Metadata:true --max-time 10 "http://169.254.169.254/metadata/instance/compute/resourceId?api-version=2021-01-01&format=text")
    workloadImpactName=$(uuidgen)
    startdate=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    for var in access_token subscriptionId resourceId workloadImpactName startdate; do
        if [ -z "${!var:-}" ]; then
            echo "ERROR: Variable $var is not set from metadata."
            exit 1
        fi
    done
}

#-------------------------------------------
# Trigger the Impact Reporting API
#-------------------------------------------
trigger_impact_reporting() {
    curl -X PUT "https://management.azure.com/subscriptions/${subscriptionId}/providers/Microsoft.Impact/workloadImpacts/${workloadImpactName}?api-version=2023-02-01-preview" \
         -H "Authorization: Bearer $access_token" \
         -H "Content-type: application/json" \
         -d '{
             "properties": {
                 "startDateTime": "'"$startdate"'",
                 "reportedTimeUtc": "'"$startdate"'",
                 "impactCategory": "'"$impact_category"'",
                 "impactDescription": "'"$impact_description"'",
                 "impactedResourceId": "'"$resourceId"'",
                 "additionalProperties": {
                     "PhysicalHostName": "'"$physical_hostname"'"
                 }
             }
         }'
}

#-------------------------------------------
# Main Execution Flow
#-------------------------------------------
parse_args "$@"

if [ "$impact_rp_trigger" = "true" ] && [ -n "$file_path" ]; then
    use_file_trigger
fi

get_fault_code
get_fault_code_value
get_impact_description
get_physical_hostname
retrieve_metadata

trigger_impact_reporting
echo "GHR Request sent"
