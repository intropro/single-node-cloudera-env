#! /bin/bash

source /etc/profile.d/env.sh


CONFIGDIR=/configs
PAGEPATH=$CONFIGDIR/index.html
PROPERTYFILE=$CONFIGDIR/conf/environment.properties

cd $CONFIGDIR

python users-config-builder.py --username=${CM_USERNAME} --password=${CM_PASSWORD} --hostname=${CM_HOSTNAME} --cluster-name=${CM_CLUSTER_NAME} --api-version=${CM_API_VERSION}



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
    background-color: blue;
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
<p><a href="conf/$(basename $PROPERTYFILE)">$(basename $PROPERTYFILE)</a></p>
<p><a href="conf/hdfs-site.xml">hdfs-site.xml</a><br>
<a href="conf/core-site.xml">core-site.xml</a><br>
<a href="conf/hbase-site.xml">hbase-site.xml</a><br>
<a href="conf/hive-site.xml">hive-site.xml</a><br>
<a href="conf/yarn-site.xml">yarn-site.xml</a></p>
<h2>Parameters:</h2>

<table id="t01">

  <tr>
    <th>property</th>
    <th>value</th>
  </tr>

$(while read i; do echo "  <tr>"; echo "<td>$(echo $i | awk -F "=" '{print $1}')</td>"; echo "<td>$(echo $i | awk -F "=" '{print $2}')</td>"; echo " </tr>"; done < $PROPERTYFILE)

</table>
</body>
</html>

EOF
