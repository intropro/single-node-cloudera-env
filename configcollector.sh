#! /bin/bash

SCRIPTNAME=$(readlink -f $0)
SCRIPTPATH=$(dirname $SCRIPTNAME)

source /etc/profile.d/env.sh

CONFIGDIR=/configs
PAGEPATH=/configs/index.html
SERVICES="hdfs yarn hbase hive"

cd $CONFIGDIR

for i in $SERVICES
    do
        curl -O "$CLUSTERMOUNTPOINT/services/$i/clientConfig"
        unzip -o $CONFIGDIR/clientConfig
    done


cat > $PAGEPATH << EOF
<!DOCTYPE html>
<html>
<head>
<style>
table {
    width:90%;
    margin-left: auto;
    margin-right: auto;
}
table, th, td {
    border: 1px solid black;
    border-collapse: collapse;
}
th, td {
    padding: 5px;
    text-align: left;
}
table#t01 tr:nth-child(even) {
    background-color: #eee;
}
table#t01 tr:nth-child(odd) {
   background-color:#fff;
}
table#t01 th    {
    background-color: black;
    color: white;
}
</style>
</head>
<body>

<h1>$CM_HOSTNAME environment configuration:</h1>
<h2>Links:</h2>
<p>ClouderaManager: <a href="http://$CM_HOSTNAME:7180">http://$CM_HOSTNAME:7180</a></p>
<p>HUE: <a href="http://$CM_HOSTNAME:8888">http://$CM_HOSTNAME:8888</a></p>
<h2>Configs:</h2>
<p><a href="hadoop-conf/hdfs-site.xml">hdfs-site.xml</a><br>
<a href="hadoop-conf/core-site.xml">core-site.xml</a><br>
<a href="hbase-conf/hbase-site.xml">hbase-site.xml</a><br>
<a href="hive-conf/hive-site.xml">hive-site.xml</a><br>
<a href="yarn-conf/yarn-site.xml">yarn-site.xml</a></p>
<h2>Parameters:</h2>
<p>HDFS:<br>
fs.defaultFS = $(xmlstarlet sel -t -m "//property[name='fs.defaultFS']" -v value yarn-conf/core-site.xml)<br>
YARN:<br>
yarn.resourcemanager.address = $(xmlstarlet sel -t -m "//property[name='yarn.resourcemanager.address']" -v value yarn-conf/yarn-site.xml)<br>
HBASE:<br>
hbase.zookeeper.quorum = $(xmlstarlet sel -t -m "//property[name='hbase.zookeeper.quorum']" -v value hbase-conf/hbase-site.xml)<br>
hbase.zookeeper.property.clientPort = $(xmlstarlet sel -t -m "//property[name='hbase.zookeeper.property.clientPort']" -v value hbase-conf/hbase-site.xml)<br>
HIVE:<br>
hive.metastore.uris = $(xmlstarlet sel -t -m "//property[name='hive.metastore.uris']" -v value hive-conf/hive-site.xml)<br>
hive.zookeeper.quorum = $(xmlstarlet sel -t -m "//property[name='hive.zookeeper.quorum']" -v value hive-conf/hive-site.xml)<br>
hive.zookeeper.client.port = $(xmlstarlet sel -t -m "//property[name='hive.zookeeper.client.port']" -v value hive-conf/hive-site.xml)<br>
</p>
</body>
</html>
EOF
