#!/usr/bin/env python

import os
import sys
import json
import base64
import optparse

import httplib
import urllib
import urlparse

import zipfile
import shutil

import contextlib

import xml.etree.ElementTree as ET


class ConfigBuilder(object):

    def __init__(self, username, password, hostname, cluster_name, api_version, tmp_dir='tmp/', conf_dir='conf/'):

        self.username = username
        self.password = password
        self.config = dict()

        if not hostname:
            raise RuntimeError('Incorrect hostname, hostname: %s' % name)
        else:
            self.hostname = hostname

        if not cluster_name:
            raise RuntimeError('Incorrect cluster name, cluster_name: %s' % cluster_name)
        else:
            self.cluster_name = cluster_name

        if not api_version:
            raise RuntimeError('Incorrect API version, api_version: %s' % api_version)
        else:
            self.api_version = api_version

        if tmp_dir and os.path.isdir(tmp_dir):
            self.tmp_dir = tmp_dir
        elif tmp_dir:
            os.makedirs(tmp_dir)
            self.tmp_dir = tmp_dir
        else:
            raise RuntimeError('The path to temporary directory cannot be None')

        if conf_dir and os.path.isdir(conf_dir):
            self.conf_dir = conf_dir
        elif conf_dir:
            os.makedirs(conf_dir)
            self.conf_dir = conf_dir
        else:
            raise RuntimeError('The path to directory with configurations cannot be None')




    def get_url(self, url, basic_auth=False, repeat_count=0):

        conn = None

        parsed_url = urlparse.urlparse(url)
        if parsed_url.scheme == 'http':
            conn = httplib.HTTPConnection(*parsed_url.netloc.split(':'))
        elif parsed_url.scheme == 'https':
            conn = httplib.HTTPSConnection(*parsed_url.netloc.split(':'))
        else:
            raise RuntimeError('Unknown scheme: %s' % url)

        headers={}
        if basic_auth:
            headers['Authorization'] = "Basic %s" % base64.encodestring('%s:%s' % (self.username, self.password))[:-1]

        conn.request('GET', parsed_url.path, headers=headers)
        resp = conn.getresponse()
        if resp.status == 401 and repeat_count < 1:
            resp = self.get_url(url, basic_auth=True, repeat_count=repeat_count+1)

        return resp


    def config_dump(self):

        URL_TEMPLATE = "http://{hostname}:7180/api/v{api_version}/cm/deployment"
        URL = URL_TEMPLATE.format(
                    hostname=self.hostname,
                    api_version=self.api_version,
                    cluster_name=self.cluster_name
        )
        resp = self.get_url(URL)
        if resp.status == 200:
            try:
                self.config = json.loads(resp.read())
            except Exception, err:
                raise RuntimeError('Cannot get the list of services, error: %s' % err)


    def services(self):

        for cluster in self.config['clusters']:
            if cluster['displayName'] == self.cluster_name:
                return [service['name'] for service in cluster['services']]
        return []


    def stream2file(self, service_name, stream):
        ''' save service config
        '''
        config_path = os.path.join(self.tmp_dir, '%s.zip' % service_name)
        with open(config_path, 'wb') as config:
            config.write(stream.read())
        with contextlib.closing(zipfile.ZipFile(config_path)) as zipped_config:
            zipped_config.extractall(self.tmp_dir)
        os.remove(config_path)


    def save_config(self, service_name):

        URL_TEMPLATE = "http://{hostname}:7180/api/v{api_version}/clusters/{cluster_name}/services/{service_name}/clientConfig"
        URL = URL_TEMPLATE.format(
                    hostname=self.hostname,
                    api_version=self.api_version,
                    cluster_name=urllib.quote(self.cluster_name),
                    service_name=service_name
        )
        resp = self.get_url(URL)
        headers = dict(resp.getheaders())
        if headers['content-type'] == 'application/json':
            return
        elif headers['content-type'] == 'application/octet-stream':
            self.stream2file(service_name, resp)


    def prepare_conf(self):

        shutil.copyfile(os.path.join(self.tmp_dir, 'hadoop-conf/hdfs-site.xml'), 'conf/hdfs-site.xml')
        shutil.copyfile(os.path.join(self.tmp_dir, 'hadoop-conf/core-site.xml'), 'conf/core-site.xml')
        shutil.copyfile(os.path.join(self.tmp_dir, 'hbase-conf/hbase-site.xml'), 'conf/hbase-site.xml')
        shutil.copyfile(os.path.join(self.tmp_dir, 'hive-conf/hive-site.xml'), 'conf/hive-site.xml')
        shutil.copyfile(os.path.join(self.tmp_dir, 'yarn-conf/yarn-site.xml'), 'conf/yarn-site.xml')


    def get_hostname(self, host_id):

        for host in self.config['hosts']:
            if host['hostId'] == host_id:
                return host['hostname']
        return None


    def get_oozie_host(self):

        host = None
        for cluster in self.config['clusters']:
            if cluster['displayName'] == self.cluster_name:
                try:
                    oozie_service = [service for service in cluster['services'] if service['name'] == 'oozie'][0]
                    host_id = oozie_service['roles'][0]['hostRef']['hostId']
                except Exception, err:
                    raise RuntimeError('Cannot find Oozie server host, error: %s' % err)
        return self.get_hostname(host_id)


    def xml2dict(self, filename):

        result = list()
        for prop in ET.parse(filename).getroot():
            result.append(dict([(c.tag, c.text) for c in prop.getchildren()]))

        return result

    def prepare_evn_props(self):

        env_props = {
            'oozieServer': "http://%s:11000" % self.get_oozie_host(),
            'sshUserName': 'bigdata',
            'sshPassword': 'bigdata',
            'sshPort': 22,
        }

        # handling core-site.xml
        for prop in self.xml2dict(os.path.join(self.conf_dir, 'core-site.xml')):
            if prop['name'] == 'fs.defaultFS':
                env_props['nameNode'] = prop['value']

            if prop['name'] == 'hadoop.security.authentication':
                env_props['securityAuthentication'] = prop['value']

        # handling yarn-site.xml
        for prop in self.xml2dict(os.path.join(self.conf_dir, 'yarn-site.xml')):
            if prop['name'] == 'yarn.resourcemanager.address':
                env_props['jobTracker'] = prop['value']

        # handling hbase-site.xml
        for prop in self.xml2dict(os.path.join(self.conf_dir, 'hbase-site.xml')):
            if prop['name'] == 'hbase.zookeeper.quorum':
                env_props['hbaseZookeeperQuorum'] = prop['value']

        # handling hive-site.xml
        for prop in self.xml2dict(os.path.join(self.conf_dir, 'hive-site.xml')):
            if prop['name'] == 'hive.zookeeper.quorum':
                env_props['hiveZookeeperQuorum'] = prop['value']
                env_props['zookeeperQuorum'] = prop['value']

            if prop['name'] == 'hive.metastore.uris':
                env_props['hiveMetastoreUris'] = prop['value']

            if prop['name'] == 'hive.metastore.kerberos.principal':
                env_props['hiveMetastorePrincipal'] = prop['value']

        with open(os.path.join(self.conf_dir, 'environment.properties'), 'w') as env:
            for k,v in env_props.items():
                env.write("%s=%s\n" % (k,v))




if __name__ == '__main__':

    parser = optparse.OptionParser(usage="usage: %prog [options]")
    parser.add_option('--username', type=str, help='CM username')
    parser.add_option('--password', type=str, help='CM password')
    parser.add_option('--hostname', type=str, help='CM hostname')
    parser.add_option('--cluster-name', type=str, help='CM cluster name')
    parser.add_option('--api-version', type=str, help='CM API version')
    parser.add_option('--tmp-dir', type=str, help='the path to temporary directory (optional, default tmp/)')
    parser.add_option('--conf-dir', type=str, help='the path to config directory (optional, default conf/)')

    opts, args = parser.parse_args()

    if not opts.username or not opts.password or not opts.hostname or not opts.cluster_name or not opts.api_version:
        parser.print_help()
        sys.exit(1)

    if not opts.tmp_dir:
        opts.tmp_dir = 'tmp/'

    if not opts.conf_dir:
        opts.conf_dir = 'conf/'

    builder = ConfigBuilder(
        username=opts.username,
        password=opts.password,
       hostname=opts.hostname,
        cluster_name=opts.cluster_name,
        api_version=opts.api_version,
        tmp_dir=opts.tmp_dir,
        conf_dir=opts.conf_dir
    )

    builder.config_dump()
    for service in builder.services():
        print service
        builder.save_config(service)
    builder.prepare_conf()
    builder.prepare_evn_props()


