#!/bin/bash

set -x

CONFDIR="/data/config"
CONFURI="http://config.goodrain.me/apps/logstash"
LSCONFIG="00logstash.conf"
RETRY=" -s --connect-timeout 3 --max-time 3  --retry 5 --retry-delay 0 --retry-max-time 10 "

SERVICE_NAME=${SERVICE_NAME:-NONE}
SERVICE_ID=${SERVICE_ID:-NONE}
ELASTICSEARCH_HOST=${ELASTICSEARCH_HOST:-127.0.0.1}
ELASTICSEARCH_PORT=${ELASTICSEARCH_PORT:-9200}

# 初始化创建目录
[ ! -d $CONFDIR ] && mkdir $CONFDIR

# 获取配置文件
if [ "$MEMORY_SIZE" == "" ];then
  echo "Must set MEMORY_SIZE environment variable! "
  exit 1
else
  echo "memory type:$MEMORY_SIZE"
  curl $RETRY ${CONFURI}/${LSCONFIG} -o ${CONFDIR}/${LSCONFIG}
  if [ $? -ne 0 ];then
    echo "get ${MEMORY_SIZE} config error!"
    exit 1
  fi
fi

case ${REGION:-ali-sh} in 
ali-sh|aws-jp-1)
  ZMQ_IP="10.0.1.11:9243";;
ucloud-bj-1)
  ZMQ_IP="10.3.1.2:9243";;
esac

#========= processing config file ========

# input 
if [ "$REVERSE_DEPEND_SERVICE" != "" ];then
  oldIFS=$IFS  #定义一个变量为默认IFS
  IFS=,        #设置IFS为逗号
  for ser in $REVERSE_DEPEND_SERVICE
  do
    service_name=`echo $ser| cut -d ':' -f 1`
    service_id=`echo $ser| cut -d ':' -f 2`
    cp /tmp/input.tpl /data/config/${service_name}_input.conf
    sed -i -e "s/SERVICE_ID/$service_id/" \
    -e "s/SERVICE_NAME/$service_name/" \
    -e "s/ZMQ_IP/$ZMQ_IP/"
    /data/config/${service_name}_input.conf
  done
else
cat > $CONFDIR/default_input.conf < EOF
input {
  stdin {
  }
}
EOF
fi

IFS=$oldIFS  #还原IFS为默认值

# output
sed -i -e "s/ELASTICSEARCH_HOST/$ELASTICSEARCH_HOST/" \
       -e "s/ELASTICSEARCH_PORT/$ELASTICSEARCH_PORT/" \
       ${CONFDIR}/${LSCONFIG}

#===========================================


# Add logstash as command if needed
if [ "${1:0:1}" = '-' ]; then
	set -- logstash "$@"
fi

# Run as user "logstash" if the command is "logstash"
if [ "$1" = 'logstash' ]; then
	set -- gosu logstash "$@"
fi

exec "$@"
