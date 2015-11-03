FROM centos:centos6

ENV PARCELDIR /opt/cloudera/parcel-repo
ENV PARCELCACHE /opt/cloudera/parcel-cache

# Environment
ENV JDKVERSION 1.8.0_60
ENV JDKDOWNLOADPATH http://download.oracle.com/otn-pub/java/jdk/8u60-b26/jdk-8u60-linux-x64.rpm
ENV JCEPOLICYDOWNLOADPATH http://download.oracle.com/otn-pub/java/jce/8/jce_policy-8.zip

ENV CDHVERSION 5.4.8
ENV PARCELDIRDOWNLOAD http://archive.cloudera.com/cdh5/parcels/5.4.8.4/
ENV PARCELFILENAME CDH-5.4.8-1.cdh5.4.8.p0.4-el6.parcel

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
        -O /tmp/jdk-$JDKVERSION-x64.rpm \
        --no-check-certificate \
        -c \
        --header "Cookie: oraclelicense=accept-securebackup-cookie" \
        $JDKDOWNLOADPATH && \
        rpm -Uhv /tmp/jdk-$JDKVERSION-x64.rpm && \
        rm -f /tmp/jdk-$JDKVERSION-x64.rpm
# Install unlimited security policy for JAVA
RUN wget \
        -O /tmp/JCE.zip \
        --no-check-certificate \
        -c \
        --header "Cookie: oraclelicense=accept-securebackup-cookie" \
        $JCEPOLICYDOWNLOADPATH && \
        unzip -d /tmp/ /tmp/JCE.zip && \
        cp -vf /tmp/UnlimitedJCEPolicyJDK?/US_export_policy.jar /usr/java/jdk$JDKVERSION/jre/lib/security/ && \
        cp -vf /tmp/UnlimitedJCEPolicyJDK?/local_policy.jar /usr/java/jdk$JDKVERSION/jre/lib/security/ && \
        rm -rf /tmp/*

# Install Cloudera repository
RUN wget \
        -O /etc/yum.repos.d/cloudera-manager.repo \
        http://archive.cloudera.com/cm5/redhat/6/x86_64/cm/cloudera-manager.repo && \
        rpm --import http://archive.cloudera.com/cdh5/redhat/6/x86_64/cdh/RPM-GPG-KEY-cloudera
# Change CM version
RUN sed -i "s/^baseurl.*/baseurl=http:\/\/archive.cloudera.com\/cm5\/redhat\/6\/x86_64\/cm\/$CDHVERSION\//" /etc/yum.repos.d/cloudera-manager.repo

RUN yum install --nogpgcheck localinstall -y \
                    cloudera-manager-daemons \
                    cloudera-manager-server \
                    cloudera-manager-server-db-2 \
                    cloudera-manager-agent

# Set timezone
RUN cp -rf /usr/share/zoneinfo/GMT /etc/localtime

# Download parcel
RUN wget -P $PARCELCACHE $PARCELDIRDOWNLOAD/$PARCELFILENAME && \
    wget -P $PARCELCACHE $PARCELDIRDOWNLOAD/$PARCELFILENAME.sha1 && \
    cp -p $PARCELCACHE/$PARCELFILENAME.sha1 $PARCELCACHE/$PARCELFILENAME.sha

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
ADD scripts/configcollector.sh /deploy/
ADD scripts/autodeploy.sh /deploy/
ADD templates/etalon.json /deploy/
# ADD configs/etalon_kerb.json /deploy/

# RUN sed -i 's/#Port 22/Port 8822/' /etc/ssh/sshd_config

RUN printf "CM_USERNAME=admin\n\
CM_PASSWORD=admin\n\
CM_AUTH=\"\$CM_USERNAME:\$CM_PASSWORD\"\n\
CM_CLUSTER_NAME='Cluster1'\n\
CM_API_VERSION=9\n\
CM_HOSTNAME=\"\$(hostname -f)\"\n\
CLUSTERMOUNTPOINT=\"http://\$CM_HOSTNAME:7180/api/v\$CM_API_VERSION/clusters/\$CM_CLUSTER_NAME\"\n\
CMMOUNTPOINT=\"http://\$CM_HOSTNAME:7180/api/v\$CM_API_VERSION/cm\"\n\
COMMANDSMOUNTPOINT=\"http://\$CM_HOSTNAME:7180/api/v\$CM_API_VERSION/commands\"\n\

PARCELNAME=\"$(echo $PARCELFILENAME | sed 's/CDH-//;s/-el6.parcel//')\"\n\
CDHVERSION=\"CDH5\"\n\
FULLCDHVERSION=\"$CDHVERSION\"\n\
" > /etc/profile.d/env.sh && chmod +x /etc/profile.d/env.sh


CMD supervisord