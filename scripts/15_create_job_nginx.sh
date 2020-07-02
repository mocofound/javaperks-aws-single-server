
#!/bin/bash

echo "Creating nginx file..."
sudo bash -c "cat >/root/jobs/nginx.nomad" <<EOF
job "nginx" {
  datacenters = ["$REGION"]

  group "nginx" {
    count = 1

    task "nginx" {
      driver = "docker"

      config {
        image = "nginx"

        port_map {
          http = 80
        }

        volumes = [
          "local:/etc/nginx/conf.d",
        ]
      }

      template {
        data = <<EOF
upstream backend {
{{ range service "demo-webapp" }}
  server {{ .Address }}:{{ .Port }};
{{ else }}server 127.0.0.1:65535; # force a 502
{{ end }}
}

server {
   listen 80;

   location / {
      proxy_pass http://backend;
   }
}
EOF

        destination   = "local/load-balancer.conf"
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }

      resources {
        network {
          mbits = 10

          port "http" {
            static = 8080
          }
        }
      }

      service {
        name = "nginx"
        port = "http"
      }
    }
  }
}
EOF

# Submit nginx job
curl \
    --request POST \
    --data @/root/jobs/nginx.nomad \
    http://nomad-server.service.$REGION.consul:4646/v1/jobs

# Wait for nginx to come online
STATUS=""
SVCCNT=0
echo "Waiting for nginx to become healthy..."
while [ "$STATUS" != "passing" ]; do
        sleep 2
        STATUS="passing"
        SVCCNT=$(($SVCCNT + 1))
        if [ $SVCCNT -gt 20 ]; then
            echo "...status check timed out for nginx"
            break
        fi
        curl -s http://127.0.0.1:8500/v1/health/service/nginx > nginx-status.txt
        outcount=`cat nginx-status.txt  | jq -r '. | length'`
        for ((oc = 0; oc < $outcount ; oc++ )); do
                incount=`cat nginx-status.txt  | jq -r --argjson oc $oc '.[$oc].Checks | length'`
                for ((ic = 0; ic < $incount ; ic++ )); do
                        indstatus=`cat nginx-status.txt  | jq -r --argjson oc $oc --argjson ic $ic '.[$oc].Checks[$ic].Status'`
                        if [ "$indstatus" != "passing" ]; then
                                STATUS=""
                        fi
                done
        done
        rm nginx-status.txt
        if [ "$indstatus" != "passing" ]; then
                echo "...checking openldap again"
        fi
done

# wait for nginx to become active

sleep 5

STATUS=""
SVCCNT=0
while [ "$STATUS" != "top" ]; do
    SVCCNT=$(($SVCCNT + 1))
    if [ $SVCCNT -gt 20 ]; then
        echo "...status check timed out for nginx"
        break
    fi
    sleep 2
    STATUS=$(curl -s ldap://$CLIENT_IP:389 | sed -n -e '0,/^\tobjectClass/p' | awk -F ": " '{print $2}' | sed '/^$/d')
    if [ "$STATUS" != "top" ]; then
        echo "...checking nginx again"
    fi
done
echo "Done."
