#!/bin/bash
# Deploy Hi Mem API to EC2
# Usage: ./api/deploy.sh

set -e

SERVER="ec2-user@44.210.125.40"
KEY="$HOME/.ssh/himem-api-key.pem"
REMOTE_DIR="~/himem-api"

echo "Deploying to $SERVER..."

scp -i "$KEY" "$(dirname "$0")/main.py" "$SERVER:$REMOTE_DIR/main.py"

ssh -i "$KEY" "$SERVER" "sudo systemctl restart himem-api && sudo systemctl status himem-api --no-pager"

echo "Done."
