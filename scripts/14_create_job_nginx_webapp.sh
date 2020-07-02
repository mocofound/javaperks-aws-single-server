#!/bin/bash

echo "Creating customer api job file..."
sudo bash -c "cat >/root/jobs/webapp.nomad" <<EOF
job "demo-webapp" {
  datacenters = ["$REGION"]

  group "demo" {
    count = 3

    task "server" {
      env {
        PORT    = "${NOMAD_PORT_http}"
        NODE_IP = "${NOMAD_IP_http}"
      }

      driver = "docker"

      config {
        image = "hashicorp/demo-webapp-lb-guide"
      }

      resources {
        network {
          mbits = 10
          port  "http"{}
        }
      }

      service {
        name = "demo-webapp"
        port = "http"

        check {
          type     = "http"
          path     = "/"
          interval = "2s"
          timeout  = "2s"
        }
      }
    }
  }
}
EOF

echo "Submitting webapp api job..."
curl \
    --request POST \
    --data @/root/jobs/webapp.nomad \
    http://nomad-server.service.$REGION.consul:4646/v1/jobs

# Wait for webapp services to come online
STATUS=""
SVCCNT=0
echo "Waiting for webapp service to become healthy..."
while [ "$STATUS" != "passing" ]; do
        sleep 2
        STATUS="passing"
        SVCCNT=$(($SVCCNT + 1))
        if [ $SVCCNT -gt 20 ]; then
            echo "...status check timed out"
            break
        fi
        curl -s http://127.0.0.1:8500/v1/health/service/webapp > webapp.txt
        outcount=`cat webapp.txt  | jq -r '. | length'`
        for ((oc = 0; oc < $outcount ; oc++ )); do
                incount=`cat webapp.txt  | jq -r --argjson oc $oc '.[$oc].Checks | length'`
                for ((ic = 0; ic < $incount ; ic++ )); do
                        indstatus=`cat webapp.txt  | jq -r --argjson oc $oc --argjson ic $ic '.[$oc].Checks[$ic].Status'`
                        if [ "$indstatus" != "passing" ]; then
                                STATUS=""
                        fi
                done
        done
        rm webapp.txt
        if [ "$indstatus" != "passing" ]; then
                echo "...checking again"
        fi
done
echo "Done."
