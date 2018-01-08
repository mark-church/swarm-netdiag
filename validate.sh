#!/bin/bash
DEBUG=1
cmd=${1:-""}

function validationLoop() {

    for svc in $svcList; do
        echo "Validating SD for service $svc"

        #svcID=$(docker service inspect $svc | jq -r '.[].ID')
        svcID=$(docker service ls | grep -w $svc | awk '{print $1}')

        taskList=$(docker service ps $svcID | grep Running | awk '{print $1}')

        for task in $taskList; do
          # docker inspect $taskList | jq -r --arg networkID "$networkID" '.[].NetworksAttachments[] | select(.Network.ID == $networkID) | .Addresses[]' | cut -d '/' -f 1 > taskIPs
            docker inspect $task | grep -A1 Addresses | tail -1 |cut -d '"' -f 2 | cut -d '/' -f 1 >> taskIPs
        done

        docker exec $ctrID nslookup tasks.$svc 2> /dev/null | grep 'Address' | awk '{print $2}' | grep -v '#'> sdIPs

        sort sdIPs > sorted-sdIPs
        sort taskIPs > sorted-taskIPs
        diff sorted-sdIPs sorted-taskIPs > result

        if [ -s result ]; then
            echo " - SD for service $svc not converged"
            echo " - The following IP addresses do not match:"
            cat result | grep -E "<|>" |  awk '{print $2}'
        else
            echo " - SD for service $svc operating normally"
        fi
        rm -f taskIPs
    done
}


function init() {
    ctrID=$(docker ps | grep "tshoot-svc" | grep "Up" | grep -v "CONTAINER" | awk '{print $1}')
    #networkID=$(docker network inspect $network | jq -r '.[].Id')
    networkID=$(docker network ls | grep $network | awk '{print $1}')

    if [ $serviceName == "all" ]; then
        svcList=$(docker service ls | grep -v "REPLICAS" |  awk '{print $2}')
    else
        svcList=$serviceName
    fi

    if [ -f "taskIPs" ]
    then
        rm -f taskIPs
    fi
}

if [ "$cmd" == "sd" ]; then

    # If serviceName="all" then will loop all services
    serviceName=$2
    network=$3

    echo "Swarm service discovery initializing."
    init
    echo "Initialization complete."
    echo ""

    validationLoop

else
    echo "Incorrect usage"
    echo ""
    echo "Usage:    ./validate.sh sd all|<service-name> <network-name>"
    echo ""
fi
