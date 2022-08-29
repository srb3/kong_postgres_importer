FROM amazonlinux
RUN amazon-linux-extras install epel -y
RUN yum install inotify-tools -y
COPY refresh.sh /usr/local/bin
ENTRYPOINT ["/usr/local/bin/refresh.sh"]
