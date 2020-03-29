#!/bin/bash

echo "Creating nvidia smi job file..."
sudo bash -c "cat >/root/jobs/nvidia-gpu-smi-job.nomad" <<EOF
job "gpu-test" {
  datacenters = ["$REGION"],
  type = "batch"

  group "smi" {
    task "smi" {
      driver = "docker"

      config {
        image = "nvidia/cuda:9.0-base"
        command = "nvidia-smi"
      }

      resources {
        device "nvidia/gpu" {
          count = 1

          # Add an affinity for a particular model
          affinity {
            attribute = "${device.model}"
            value     = "Tesla K80"
            weight    = 50
          }
        }
      }
    }
  }
}
        
EOF

echo "Submitting nvidia gpu smi job..."
curl \
    --request POST \
    --data @/root/jobs/nvidia-gpu-smi-job.nomad \
    http://nomad-server.service.$REGION.consul:4646/v1/jobs

# Wait for product api services to come online
STATUS=""
SVCCNT=0
echo "Waiting for nvidia-gpu service to become healthy..."
while [ "$STATUS" != "passing" ]; do
        sleep 2
        STATUS="passing"
        SVCCNT=$(($SVCCNT + 1))
        if [ $SVCCNT -gt 20 ]; then
            echo "...status check timed out"
            break
        fi
        curl -s http://127.0.0.1:8500/v1/health/service/nvidia-gpu > nvidia-gpu-status.txt
        outcount=`cat nvidia-gpu-status.txt  | jq -r '. | length'`
        for ((oc = 0; oc < $outcount ; oc++ )); do
                incount=`cat nvidia-gpu-status.txt  | jq -r --argjson oc $oc '.[$oc].Checks | length'`
                for ((ic = 0; ic < $incount ; ic++ )); do
                        indstatus=`cat nvidia-gpu-status.txt  | jq -r --argjson oc $oc --argjson ic $ic '.[$oc].Checks[$ic].Status'`
                        if [ "$indstatus" != "passing" ]; then
                                STATUS=""
                        fi
                done
        done
        rm nvidia-gpu-status.txt
        if [ "$indstatus" != "passing" ]; then
                echo "...checking again"
        fi
done
echo "Done."
