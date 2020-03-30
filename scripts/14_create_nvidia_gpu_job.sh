#!/bin/bash

#working.  replace json job below with this one.
job "nvidia-gpu-job" {
  datacenters = ["us-east-1"]
  type = "service"

  update {
  progress_deadline = "1h"
  }

  group "nvidia-gpu-group" {
    task "nvidia-gpu" {
      driver = "docker"

      config {
        image = "linuxserver/foldingathome:7.5.1-ls1"
        port_map {
          svc = 7396
        }
      }

      resources {
        network {
          port "svc" {}
        }
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


echo "Creating nvidia gpu job file..."
sudo bash -c "cat >/root/jobs/nvidia-gpu-job.nomad" <<EOF
{
    "Job": {
        "ID": "nvidia-gpu-job",
        "Name": "nvidia-gpu-api",
        "Type": "service",
        "Datacenters": ["$REGION"],
        "TaskGroups": [{
            "Name": "nvidia-gpu-group",
            "Count": 3,
            "Tasks": [{
                "Name": "nvidia-gpu",
                "Driver": "docker",
                "Vault": {
                    "Policies": ["access-creds"]
                },
                "Config": {
                    "image": "linuxserver/foldingathome:7.5.1-ls1",
                    "port_map": [{
                        "svc": 7396
                    }]
                },
                "Templates": [{
                    "EmbeddedTmpl": "{{with secret \"secret/data/aws\"}}\nAWS_ACCESS_KEY = \"{{.Data.data.aws_access_key}}\"\nAWS_SECRET_KEY = \"{{.Data.data.aws_secret_key}}\"\n{{end}}\nAWS_REGION = \"$REGION\"\nDDB_TABLE_NAME = \"$TABLE_PRODUCT\"\n",
                    "DestPath": "secrets/file.env",
                    "Envvars": true
                }],
                "Resources": {
                     "Device": [{
                        "Name": "nvidia/gpu",
                        "count" = 1
                        }],
                    "CPU": 100,
                    "MemoryMB": 80,
                    "Networks": [{
                        "MBits": 1,
                        "DynamicPorts": [
                            {
                                "Label": "svc",
                                "Value": 0
                            }
                        ]
                    }]
                },
                "Services": [{
                    "Name": "nvidia-gpu",
                    "PortLabel": "svc"
                }]
            }],
            "Update": {
                "MaxParallel": 3,
                "MinHealthyTime": 10000000000,
                "HealthyDeadline": 180000000000,
                "AutoRevert": false,
                "AutoPromote": false,
                "Canary": 1
            }
        }]
    }
}
EOF

echo "Submitting nvidia gpu job..."
curl \
    --request POST \
    --data @/root/jobs/nvidia-gpu-job.nomad \
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

