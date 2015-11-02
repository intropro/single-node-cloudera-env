#! /usr/bin/env bash

SCRIPTNAME=$(readlink -f $0)
SCRIPTPATH=$(dirname $SCRIPTNAME)

source /etc/profile.d/env.sh

CM_SERVICES="cloudera-scm-server-db cloudera-scm-server cloudera-scm-agent"

FIRSTRUNFLAG="/var/lib/.cloudera-manager"

function ensure_user_is_root() {
    if [[ "$EUID" -ne "0" ]]; then
        echo "You must run this script as root. Try 'sudo ${0} ${@}'."
        exit 1
    fi
}

function log() {
    echo "[$(date +"%T")][QuickStart] ${1}"
}

function jobfinwait ()
{
    local JOBWAITID="$@"
    local CHECKJOBSTAT="curl -sS -u $CM_AUTH \
    "$COMMANDSMOUNTPOINT/$JOBWAITID" | jq '.success'"

    while [[ "$(eval $CHECKJOBSTAT)" == "null" ]]
    do
        log "Waiting for success of JOBID=$JOBWAITID"
        sleep 10
    done

    if [[ "$(eval $CHECKJOBSTAT)" == "true" ]]
    then
        log "JOBID=$JOBWAITID succeeded"
    else
        log "JOBID=$JOBWAITID fail. Check Cloudera Manager for details."
        exit 1
    fi
}


function waitcm ()
{
    nc -z $CM_HOSTNAME 7180

    while [[ "$?" == "1" ]]
        do
            log "Waiting for Cloudera Manager to be started"
            sleep 5
            nc -z $CM_HOSTNAME 7180
        done
    echo DONE
}

function startcm ()
{
    for i in $CM_SERVICES
        do
            service $i start
        done
    service ntpd start
    service haveged start
}

function firstdeploy ()
{
    # Check host id
    HOSTID=$(curl -Ss -u $CM_AUTH -X GET "http://$CM_HOSTNAME:7180/api/v$CM_API_VERSION/hosts" | jq -r '.[] | .[] | .hostId')

    # Create cluster
    curl -u $CM_AUTH -X POST -H "Content-Type:application/json" \
        -d "{ \"items\":
            [{\"name\" : \"$CM_CLUSTER_NAME\",
            \"displayName\" : \"$CM_CLUSTER_NAME\",
            \"version\" : \"$CDHVERSION\",
            \"fullVersion\" : \"$FULLCDHVERSION\"}]
            }" "http://$CM_HOSTNAME:7180/api/v$CM_API_VERSION/clusters"
    # Add host to cluster
    curl -u $CM_AUTH -X POST -H "Content-Type:application/json" \
    -d "{ \"items\":
    [{\"hostId\" : \"$HOSTID\"}] }" "$CLUSTERMOUNTPOINT/hosts"

    # Check and activate dowloaded parcel
    # In order to manually select a version comment out the line
    PARCELNAME=$(curl -Ss -u $CM_AUTH -X GET "$CLUSTERMOUNTPOINT/parcels" | jq -r -c '.[] | .[] | select(.stage == "DOWNLOADED")  | .version' | grep $FULLCDHVERSION | tail -n 1)

    if [[ -z "$PARCELNAME" ]]
        then
            log "There no correct parcel version avaliable. Please check script environment."
            exit 1
        fi

    # Distribute parcel
    curl -u $CM_AUTH -X POST "$CLUSTERMOUNTPOINT/parcels/products/CDH/versions/$PARCELNAME/commands/startDistribution"
    while [[ $(curl -Ss -u $CM_AUTH -X GET "$CLUSTERMOUNTPOINT/parcels" | jq -r -c ".[] | .[] | select(.version == \"$PARCELNAME\") | .stage") == "DISTRIBUTING" ]]
        do
            log "Waiting for parcel $PARCELNAME to be distributed"
            sleep 5
        done

    # Activate parcel
    curl -u $CM_AUTH -X POST "$CLUSTERMOUNTPOINT/parcels/products/CDH/versions/$PARCELNAME/commands/activate"
    while [[ $(curl -Ss -u $CM_AUTH -X GET "$CLUSTERMOUNTPOINT/parcels" | jq -r -c ".[] | .[] | select(.version == \"$PARCELNAME\") | .stage") != "ACTIVATED" ]]
        do
            log "Waiting for parcel $PARCELNAME to be activated"
            sleep 5
        done

    cp $SCRIPTPATH/etalon.json $SCRIPTPATH/$CM_CLUSTER_NAME.json

    sed -i "s/HOSTIDPLACEHOLDER1/$HOSTID/g" $SCRIPTPATH/$CM_CLUSTER_NAME.json
    sed -i "s/HOSTNAMEPLACEHOLDER1/$CM_HOSTNAME/g" $SCRIPTPATH/$CM_CLUSTER_NAME.json
    sed -i "s/HOSTIPPLACEHOLDER1/$(hostname -i)/g" $SCRIPTPATH/$CM_CLUSTER_NAME.json
    curl --upload-file $SCRIPTPATH/$CM_CLUSTER_NAME.json -u $CM_AUTH "$CMMOUNTPOINT/deployment?deleteCurrentDeployment=true"

    # Make procedures for first run of services
    JOBID=$(curl -sS -u $CM_AUTH -X POST "$CLUSTERMOUNTPOINT/commands/firstRun" | jq '.id')
    jobfinwait $JOBID

    # Run cloudera services
    JOBID=$(curl -sS -u $CM_AUTH -X POST \
        "$CMMOUNTPOINT/service/commands/start" | jq '.id')
    jobfinwait $JOBID

}

function afterfirstdeploy ()
{
    JOBID=$(curl -sS -u $CM_AUTH -X POST \
        "$CMMOUNTPOINT/service/commands/restart" | jq '.id')
    jobfinwait $JOBID

    JOBID=$(curl -sS -u $CM_AUTH -X POST -H "Content-Type:application/json" \
        -d '{ "redeployClientConfiguration": "true" }' \
        "$CLUSTERMOUNTPOINT/commands/restart" | jq '.id')
    jobfinwait $JOBID
}

function configure_hadoop_env ()
{
    sudo -u hdfs hdfs dfs -mkdir /data; sudo -u hdfs hdfs dfs -chmod 777 /data
    sudo -u hdfs hdfs dfs -mkdir /app; sudo -u hdfs hdfs dfs -chmod 777 /app
    useradd bigdata; echo "bigdata:bigdata" | chpasswd
}

ensure_user_is_root

if [[ ! -e $FIRSTRUNFLAG ]]
    then
        startcm
        waitcm
        firstdeploy
        touch $FIRSTRUNFLAG
        $SCRIPTPATH/configcollector.sh
        configure_hadoop_env
    else
        startcm
        waitcm
        afterfirstdeploy
        $SCRIPTPATH/configcollector.sh
fi
