FROM centos:centos6

ENV PARCELDIR /opt/cloudera/parcel-repo
ENV PARCELCACHE /opt/cloudera/parcel-cache

# Environment
ENV JDK_VERSION 1.7.0_80
ENV JDK_DOWNLOAD_PATH http://download.oracle.com/otn-pub/java/jdk/7u80-b15/jdk-7u80-linux-x64.rpm
ENV JCE_POLICY_DOWNLOAD_PATH http://download.oracle.com/otn-pub/java/jce/7/UnlimitedJCEPolicyJDK7.zip

ENV CDH_VERSION 5.3.3
ENV PARCEL_DIR_DOWNLOAD http://archive.cloudera.com/cdh5/parcels/5.3.3/
ENV PARCEL_FILE_NAME CDH-5.3.3-1.cdh5.3.3.p0.5-el6.parcel

# Package installation
RUN yum clean all
RUN yum update -y && \
        yum install -y \
        openssh-server \
        openssh-clients \
        sudo \
        tar \
        unzip \
        vim \
        wget && \
    yum install -y \
        epel-release && \
    yum install -y \
        krb5-libs \
        krb5-workstation \
        net-tools \
        ntp \
        openldap-clients \
        python-pip \
        haveged \
        xmlstarlet \
        jq \
        nc \
        telnet \
        sshfs \
        mlocate \
        lsof

# RUN locale-gen en_US en_US.UTF-8 && dpkg-reconfigure locales
# ENV LC_ALL="en_US.UTF-8"
ENV TERM=xterm

# JAVA installation
RUN wget \
        --progress=dot:giga \
        -O /tmp/jdk-$JDK_VERSION-x64.rpm \
        --no-check-certificate \
        -c \
        --header "Cookie: oraclelicense=accept-securebackup-cookie" \
        $JDK_DOWNLOAD_PATH && \
        rpm -Uhv /tmp/jdk-$JDK_VERSION-x64.rpm && \
        rm -f /tmp/jdk-$JDK_VERSION-x64.rpm
# Install unlimited security policy for JAVA
RUN wget \
        --progress=dot:giga \
        -O /tmp/JCE.zip \
        --no-check-certificate \
        -c \
        --header "Cookie: oraclelicense=accept-securebackup-cookie" \
        $JCE_POLICY_DOWNLOAD_PATH && \
        unzip -d /tmp/ /tmp/JCE.zip && \
        cp -vf /tmp/UnlimitedJCEPolicy*/US_export_policy.jar /usr/java/jdk$JDK_VERSION/jre/lib/security/ && \
        cp -vf /tmp/UnlimitedJCEPolicy*/local_policy.jar /usr/java/jdk$JDK_VERSION/jre/lib/security/ && \
        rm -rf /tmp/*

# Install Cloudera repository
RUN wget \
        --progress=dot:giga \
        -O /etc/yum.repos.d/cloudera-manager.repo \
        http://archive.cloudera.com/cm5/redhat/6/x86_64/cm/cloudera-manager.repo && \
        rpm --import http://archive.cloudera.com/cdh5/redhat/6/x86_64/cdh/RPM-GPG-KEY-cloudera
# Change CM version
RUN sed -i "s/^baseurl.*/baseurl=http:\/\/archive.cloudera.com\/cm5\/redhat\/6\/x86_64\/cm\/$CDH_VERSION\//" /etc/yum.repos.d/cloudera-manager.repo

RUN yum install --nogpgcheck localinstall -y \
                    cloudera-manager-daemons \
                    cloudera-manager-server \
                    cloudera-manager-server-db-2 \
                    cloudera-manager-agent

# Set timezone
RUN cp -rf /usr/share/zoneinfo/GMT /etc/localtime

# Download parcel
RUN wget --progress=dot:giga -P $PARCELCACHE $PARCEL_DIR_DOWNLOAD/$PARCEL_FILE_NAME && \
    wget --progress=dot:giga -P $PARCELCACHE $PARCEL_DIR_DOWNLOAD/$PARCEL_FILE_NAME.sha1 && \
    cp -p $PARCELCACHE/$PARCEL_FILE_NAME.sha1 $PARCELCACHE/$PARCEL_FILE_NAME.sha

RUN for i in /opt/cloudera/parcel-cache/*; do ln -sf $i /opt/cloudera/parcel-repo/$(basename $i); done

RUN sed -i 's/Defaults.*requiretty.*$/#Defaults requiretty/' /etc/sudoers

RUN ssh-keygen -b 1024 -t rsa -f /etc/ssh/ssh_host_key -q -N ''
RUN ssh-keygen -b 1024 -t rsa -f /etc/ssh/ssh_host_rsa_key -q -N ''
RUN ssh-keygen -b 1024 -t dsa -f /etc/ssh/ssh_host_dsa_key -q -N ''

RUN echo "root:root" | chpasswd

RUN mkdir /var/log/supervisor && \
    ln -s /usr/lib64/cmf/agent/build/env/bin/supervisorctl /usr/bin/supervisorctl && \
    ln -s /usr/lib64/cmf/agent/build/env/bin/supervisord /usr/bin/supervisord
ADD configs/supervisord.conf /etc/
ADD scripts/start_web.sh /
RUN mkdir /configs /deploy
ADD scripts/configcollector.sh /configs/
ADD scripts/users-config-builder.py /configs/

ADD scripts/autodeploy.sh /deploy/
ADD templates/etalon.json /deploy/
ADD templates/etalon_kerb.json /deploy/

RUN sed -i 's/#Port 22/Port 8822/' /etc/ssh/sshd_config

RUN printf "CM_USERNAME=admin\n\
CM_PASSWORD=admin\n\
CM_AUTH=\"\$CM_USERNAME:\$CM_PASSWORD\"\n\
CM_CLUSTER_NAME='Cluster1'\n\
CM_API_VERSION=9\n\
CM_HOSTNAME=\"\$(hostname -f)\"\n\
CLUSTERMOUNTPOINT=\"http://\$CM_HOSTNAME:7180/api/v\$CM_API_VERSION/clusters/\$CM_CLUSTER_NAME\"\n\
CMMOUNTPOINT=\"http://\$CM_HOSTNAME:7180/api/v\$CM_API_VERSION/cm\"\n\
COMMANDSMOUNTPOINT=\"http://\$CM_HOSTNAME:7180/api/v\$CM_API_VERSION/commands\"\n\

PARCELNAME=\"$(echo $PARCEL_FILE_NAME | sed 's/CDH-//;s/-el6.parcel//')\"\n\
CDHVERSION=\"CDH5\"\n\
FULLCDHVERSION=\"$CDH_VERSION\"\n\
" > /etc/profile.d/env.sh && chmod +x /etc/profile.d/env.sh


CMD supervisord