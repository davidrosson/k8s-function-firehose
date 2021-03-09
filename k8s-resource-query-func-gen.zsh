#!/usr/bin/env zsh


########################################
# Cluster-wide K8s resources
########################################

declare -A resource_map_cluster_wide

# admissionregistration.k8s.io/v1
resource_map_cluster_wide+=(["mwh"]="mutatingwebhookconfigurations")
resource_map_cluster_wide+=(["vwh"]="validatingwebhookconfigurations")

# apiextensions.k8s.io/v1
resource_map_cluster_wide+=(["crd"]="customresourcedefinitions")

# apiregistration.k8s.io/v1
resource_map_cluster_wide+=(["apis"]="apiservices")

# certificates.k8s.io/v1beta1
resource_map_cluster_wide+=(["csr"]="certificatesigningrequests")

# core/v1
resource_map_cluster_wide+=(["cs"]="componentstatuses")
resource_map_cluster_wide+=(["ns"]="namespaces")
resource_map_cluster_wide+=(["no"]="nodes")
resource_map_cluster_wide+=(["pv"]="persistentvolumes")

# crd.k8s.amazonaws.com/v1alpha1
resource_map_cluster_wide+=(["eni"]="eniconfigs")

# node.k8s.io/v1beta1
resource_map_cluster_wide+=(["rtc"]="runtimeclasses")

# policy/v1beta1
resource_map_cluster_wide+=(["psp"]="podsecuritypolicies")

# rbac.authorization.k8s.io/v1
resource_map_cluster_wide+=(["crb"]="clusterrolebindings")
resource_map_cluster_wide+=(["cr"]="clusterroles")

# scheduling.k8s.io/v1
resource_map_cluster_wide+=(["pc"]="priorityclasses")

# storage.k8s.io/v1
resource_map_cluster_wide+=(["csid"]="csidrivers")
resource_map_cluster_wide+=(["csin"]="csinodes")
resource_map_cluster_wide+=(["sc"]="storageclasses")
resource_map_cluster_wide+=(["va"]="volumeattachments")


########################################
# Namespaced K8s resources
########################################

declare -A resource_map_namespaced

# apps/v1
resource_map_namespaced+=(["crs"]="controllerrevisions")
resource_map_namespaced+=(["ds"]="daemonsets")
resource_map_namespaced+=(["dep"]="deployments")
resource_map_namespaced+=(["rs"]="replicasets")
resource_map_namespaced+=(["sts"]="statefulsets")

# autoscaling/v1
resource_map_namespaced+=(["hpa"]="horizontalpodautoscalers")

# batch/v1
resource_map_namespaced+=(["cj"]="cronjobs")
resource_map_namespaced+=(["kj"]="jobs")

# coordination.k8s.io/v1
resource_map_namespaced+=(["lease"]="leases")

# core/v1
resource_map_namespaced+=(["cm"]="configmaps")
resource_map_namespaced+=(["ep"]="endpoints")
resource_map_namespaced+=(["lr"]="limitranges")
resource_map_namespaced+=(["pvc"]="persistentvolumeclaims")
resource_map_namespaced+=(["pod"]="pods")
resource_map_namespaced+=(["pt"]="podtemplates")
resource_map_namespaced+=(["rc"]="replicationcontrollers")
resource_map_namespaced+=(["rq"]="resourcequotas")
resource_map_namespaced+=(["sec"]="secrets")
resource_map_namespaced+=(["sa"]="serviceaccounts")
resource_map_namespaced+=(["svc"]="services")

# events.k8s.io/v1beta1
resource_map_namespaced+=(["ev"]="events")

# monitoring.coreos.com/v1
resource_map_namespaced+=(["am"]="alertmanagers")
resource_map_namespaced+=(["pm"]="podmonitors")
resource_map_namespaced+=(["prom"]="prometheuses")
resource_map_namespaced+=(["promr"]="prometheusrules")
resource_map_namespaced+=(["sm"]="servicemonitors")
resource_map_namespaced+=(["thanr"]="thanosrulers")

# networking.k8s.io/v1
resource_map_namespaced+=(["ing"]="ingresses")
resource_map_namespaced+=(["np"]="networkpolicies")

# policy/v1beta1
resource_map_namespaced+=(["pdb"]="poddisruptionbudgets")

# rbac.authorization.k8s.io/v1
resource_map_namespaced+=(["rb"]="rolebindings")
resource_map_namespaced+=(["role"]="roles")

# traefik.containo.us/v1alpha1
resource_map_namespaced+=(["ir"]="ingressroutes")
resource_map_namespaced+=(["irt"]="ingressroutetcps")
resource_map_namespaced+=(["iru"]="ingressrouteudps")
resource_map_namespaced+=(["mw"]="middlewares")
resource_map_namespaced+=(["tlso"]="tlsoptions")
resource_map_namespaced+=(["tlss"]="tlsstores")
resource_map_namespaced+=(["ts"]="traefikservices")

# vault.banzaicloud.com/v1alpha1
resource_map_namespaced+=(["vlt"]="vaults")

# vpcresources.k8s.aws/v1beta1
resource_map_namespaced+=(["sgp"]="securitygrouppolicies")


########################################
# All K8s resources
########################################

declare -A resource_map_all

for key in ${(k)resource_map_cluster_wide}; do
  resource_map_all+=([$key]=${resource_map_cluster_wide[$key]})
done

for key in ${(k)resource_map_namespaced}; do
  resource_map_all+=([$key]=${resource_map_namespaced[$key]})
done


########################################
# Functions
########################################

## Internal function, allowing `kubectl` execution with or without `aws-vault`
##
_kubectl_cmd () {
  if [[ $K8S_FF_USE_AWS_VAULT == "true" ]]; then
    aws-vault exec $AWS_PROFILE -- kubectl "$@"
  else
    kubectl "$@"
  fi
}


## Internal function, called by each dymanically-generated function, to produce K8s resource information
##
_k8s_resource_query () {
  function_name=$1
  resource_type=$2
  passed_param1=$3
  passed_param2=$4
  resource_rows=""
  resource_list_builder=""

  declare -a resource_list

  # Check whether an environment variable has been set to control whether or not to pipe kubectl's `get` and `describe` output to `less`
  [[ -n $K8S_FF_PIPE_DETAILS_TO_LESS ]] && pipe_details_to_less=$K8S_FF_SHOW_RESOURCE_TYPE || pipe_details_to_less="true"
  # Check whether an environment variable has been set to control whether or not the resource API version and type are displayed with each query
  [[ -n $K8S_FF_SHOW_RESOURCE_TYPE ]] && show_resource_type=$K8S_FF_SHOW_RESOURCE_TYPE || show_resource_type="true"

  # If an index number isn't specified in the input, then return a list of all K8s resources of the specified type
  if ! [[ $passed_param1 =~ '^[0-9]+$' ]]; then
    grep_value=""
    output_format=""

    # If additional input is provided, determine if it is an '--output' value ('wide'); else, grep for the passed value
    # The structure below allows passing either e.g. `pod wide my-demo` or `pod my-demo wide` with the same result
    if [[ -n $passed_param1 ]]; then
      [[ $passed_param1 == "wide" ]] && output_format="--output=$passed_param1" || grep_value=$passed_param1
      if [[ -n $passed_param2 ]]; then
        [[ $passed_param2 == "wide" ]] && output_format="--output=$passed_param2" || grep_value=$passed_param2
      fi
    fi

    # If the 'show_resource_type' flag is 'true', print the K8s resource type
    if [[ $show_resource_type == "true" ]]; then
      explain_resource=$(_kubectl_cmd explain $resource_type)
      # Exit gracefully on server connectivity issues
      [[ $? -ne 0 ]] && return 1
      api_version=$(echo $explain_resource | grep -w 'VERSION:' | awk '{ printf $2 }')
      [[ $api_version != "" ]] && echo -e "${api_version}/${resource_type}:\n"
    fi

    # Iterate over all resources; if none, an error message is returned (this message isn't treated as resource output)
    row=0
    while; IFS= read -r line; [[ ${#line} -gt 0 ]]; do
      # For the first row, add a new column header
      if [[ $row = 0 ]]; then
        resource_rows="INDEX   ${line}"
        ((row++))
      # Only output lines matching the grep value, if one is provided
      elif [[ $line =~ .*$grep_value.* ]]; then
        # Evenly align the gap after the index numbers, accounting for various index digit counts
        gap="   "
        [[ $row -lt 100 ]] && gap=${gap}" "
        [[ $row -lt 10 ]] && gap=${gap}" "
        # Capture the relevant K8s resources
        resource_rows+="\n$row $gap $line"
        # Build a space-separated string of all printed resources; this can be used to query K8s resources based on index
        resource_list_builder="${resource_list_builder}${resource_type}/$(echo $line | awk '{ printf $1 }') " # The space before the closing quote is necessary
        ((row++))
      fi
    done <<< $(_kubectl_cmd get $resource_type $output_format)

    # Print a message instead of the column headers if there are no results returned for a provided grep value
    if [[ $(echo -e $resource_rows | wc -l) -gt 1 ]]; then
      echo -e $resource_rows
    elif [[ $resource_rows =~ "INDEX" ]]; then
      echo "No '$resource_type' resources found in this namespace with '$grep_value' in the name."
    fi

    # Persist the displayed list of K8s resources, so nothing changes "under the covers" before querying based on index
    export K8S_FF_RESOURCE_LIST=$resource_list_builder
    # Persist the type of K8s resource present in the list, to prevent performing an index lookup with a different resource type
    export K8S_FF_RESOURCE_LIST_TYPE=$resource_type
  else
    # If no generated list of available K8s resources exists yet, provide guidance on generating it
    [[ -z $K8S_FF_RESOURCE_LIST || $K8S_FF_RESOURCE_LIST_TYPE != $resource_type ]] && echo -e "Before inspecting a specific '$resource_type' resource, run the '$function_name' command to populate the list of existing '$resource_type' resources.\nType 'help' for a list of available resource commands." && return 1

    # Create an array object from the resource list environment variable values
    for resource in $(echo $K8S_FF_RESOURCE_LIST); do
      resource_list+=($resource)
    done

    # If the parameter `d` (for `describe`) is provided, then execute `kubectl describe`; otherwise execute `kubectl get`
    if [[ $passed_param2 == "d" ]]; then
      describe_resource=$(_kubectl_cmd describe $resource_list[$passed_param1])
      [[ $pipe_details_to_less == "true" ]] && echo $describe_resource | less || echo $describe_resource
    else
      get_resource=$(_kubectl_cmd get $resource_list[$passed_param1] --output=yaml)
      [[ $pipe_details_to_less == "true" ]] && echo $get_resource | less || echo $get_resource
    fi
  fi
}


## Dynamically generates functions from the available K8s resource types defined in the array 'resource_map_all'
## The result of this loop is a number of directly-callable functions, with names derived from the 'resource_map_all' keys
## The name of each generated function is pulled from the keys of the 'resource_map_all' array; shorthand names are used
## The '$0' in the 'resource_map_all[$0]' lookup is the name of the current function, which returns a full resource type name
##
for resource in ${(k)resource_map_all}; do
  $resource () {
    function_name=$0
    resource_type=${resource_map_all[$function_name]}
    passed_param1=$1
    passed_param2=$2

    _k8s_resource_query $function_name $resource_type $passed_param1 $passed_param2
  }
done


## Print a sorted list of 'command -> resource' type mappings, to show all available function calls
##
help () {
  echo "Cluster-wide K8s resource functions:"
  for resource in $(echo ${(k)resource_map_cluster_wide} | tr ' ' '\n' | sort | tr '\n' ' '); do
    echo "  $resource -> $resource_map_cluster_wide[$resource]"
  done
  echo
  echo "Namespaced K8s resource functions:"
  for resource in $(echo ${(k)resource_map_namespaced} | tr ' ' '\n' | sort | tr '\n' ' '); do
    echo "  $resource -> ${resource_map_namespaced[$resource]}"
  done
}


## Display logs for a given Pod, selected by index; a container name may be passed if needed
##
kl () {
  [[ -z $K8S_FF_RESOURCE_LIST || $K8S_FF_RESOURCE_LIST_TYPE != "pods" ]] && echo "Before inspecting logs for a specific Pod, run the 'pod' command to populate the list of existing 'pods' resources." && return 1

  resource_list_index=$1
  container_name=$2

  declare -a resource_list

  for resource in $(echo $K8S_FF_RESOURCE_LIST); do
    resource_list+=($resource)
  done

  _kubectl_cmd logs -f $resource_list[$resource_list_index] $container_name
}


## Execute a command against a given Pod, selected by index
##
kx () {
  [[ -z $K8S_FF_RESOURCE_LIST || $K8S_FF_RESOURCE_LIST_TYPE != "pods" ]] && echo "Before executing a command on a specific Pod, run the 'pod' command to populate the list of existing 'pods' resources." && return 1

  resource_list_index=$1
  exec_command=$2

  declare -a resource_list

  for resource in $(echo $K8S_FF_RESOURCE_LIST); do
    resource_list+=($resource)
  done

  _kubectl_cmd exec -it $resource_list[$resource_list_index] -- $exec_command
}
