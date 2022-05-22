#!/bin/sh

set -e

supervisor_conf=/supervisord.conf

echo "
[supervisord]
nodaemon=true

[program:redis-trib-create]
command=sh -c 'sleep 3 && echo yes | redis-trib create --replicas 1 127.0.0.1:5000 127.0.0.1:5001 127.0.0.1:5002 127.0.0.1:5003 127.0.0.1:5004 127.0.0.1:5005'
autorestart=false
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0" > $supervisor_conf

# Initialize configs
for p in 5000 5001 5002 5003 5004 5005
do
  conf_path=/redis-$p.conf
  data_dir=/data/redis-$p

  mkdir -p $data_dir
  chown redis:redis $data_dir
  echo "
cluster-enabled yes
cluster-node-timeout 5000
cluster-config-file nodes.conf
appendonly yes
port $p
dir $data_dir
cluster-announce-ip $CLUSTER_ANNOUNCE_IP" > $conf_path

  echo "
[program:redis-$p]
command=redis-server $conf_path
autorestart=unexpected
user=redis
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0" >> $supervisor_conf
done

# Start Redis servers
supervisord -c $supervisor_conf